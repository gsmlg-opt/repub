import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:uuid/uuid.dart';

/// Service for triggering webhooks on events.
class WebhookService {
  static const _uuid = Uuid();

  final MetadataStore metadata;
  final http.Client _httpClient;

  /// Maximum number of delivery attempts before disabling a webhook.
  static const maxFailures = 5;

  /// Timeout for webhook delivery requests.
  static const deliveryTimeout = Duration(seconds: 10);

  /// Maximum number of concurrent webhook deliveries.
  static const maxConcurrentDeliveries = 5;

  /// Blocked host patterns for SSRF protection.
  /// This provides defense-in-depth at delivery time in case a webhook
  /// was created before SSRF protection was added, or via direct DB manipulation.
  static const _blockedPatterns = [
    'localhost',
    '127.', // Loopback
    '0.0.0.0',
    '10.', // Private class A
    '192.168.', // Private class C
    '169.254.', // Link-local (AWS metadata service)
    '[::1]',
    '::1', // IPv6 localhost
    'fd00:',
    'fe80:', // IPv6 private/link-local
  ];

  WebhookService({
    required this.metadata,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Check if a URL is safe to call (SSRF protection).
  /// Returns true if safe, false if blocked.
  bool _isUrlSafe(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        return false;
      }

      final host = uri.host.toLowerCase();

      // Check blocked patterns
      if (_blockedPatterns.any((pattern) => host.startsWith(pattern))) {
        return false;
      }

      // Check for private class B (172.16.0.0 - 172.31.255.255)
      if (host.startsWith('172.')) {
        final parts = host.split('.');
        if (parts.length >= 2) {
          final second = int.tryParse(parts[1]);
          if (second != null && second >= 16 && second <= 31) {
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      // Log URL parsing errors for debugging
      Logger.debug(
        'Failed to parse webhook URL for safety check',
        component: 'webhook',
        metadata: {'url': url, 'error': e.toString()},
      );
      return false;
    }
  }

  /// Trigger webhooks for an event.
  ///
  /// This method is fire-and-forget - it runs in the background and
  /// doesn't block the caller.
  Future<void> triggerEvent({
    required String eventType,
    required Map<String, dynamic> data,
  }) async {
    try {
      final webhooks = await metadata.getWebhooksForEvent(eventType);
      if (webhooks.isEmpty) return;

      Logger.debug(
        'Triggering ${webhooks.length} webhooks for $eventType',
        component: 'webhook',
      );

      final payload = WebhookPayload(
        eventType: eventType,
        timestamp: DateTime.now(),
        data: data,
      );

      // Deliver to all webhooks with concurrency limit to prevent resource exhaustion
      for (var i = 0; i < webhooks.length; i += maxConcurrentDeliveries) {
        final batch = webhooks.skip(i).take(maxConcurrentDeliveries);
        await Future.wait(batch.map((webhook) => _deliver(webhook, payload)));
      }
    } catch (e, stack) {
      Logger.error(
        'Error triggering webhooks for $eventType',
        component: 'webhook',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Deliver a payload to a webhook.
  Future<void> _deliver(Webhook webhook, WebhookPayload payload) async {
    final startTime = DateTime.now();
    int statusCode = 0;
    String? error;

    // SSRF protection: Validate URL at delivery time
    // This protects against webhooks created before SSRF protection was added
    if (!_isUrlSafe(webhook.url)) {
      error = 'Blocked: URL targets internal or private network';
      Logger.warn(
        'SSRF protection blocked webhook delivery',
        component: 'webhook',
        metadata: {
          'webhookId': webhook.id,
          'url': webhook.url,
          'event': payload.eventType,
        },
      );

      // Disable the webhook to prevent repeated attempts
      await metadata.updateWebhook(
        webhook.copyWith(
          isActive: false,
          lastTriggeredAt: DateTime.now(),
        ),
      );

      // Log the blocked delivery
      final delivery = WebhookDelivery(
        id: _uuid.v4(),
        webhookId: webhook.id,
        eventType: payload.eventType,
        payload: payload.toJson(),
        statusCode: 0,
        success: false,
        error: error,
        duration: Duration.zero,
        deliveredAt: DateTime.now(),
      );
      await metadata.logWebhookDelivery(delivery);
      return;
    }

    try {
      final body = jsonEncode(payload.toJson());
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'X-Webhook-Event': payload.eventType,
        'X-Webhook-Delivery': _uuid.v4(),
      };

      // Add HMAC signature if secret is configured
      if (webhook.secret != null && webhook.secret!.isNotEmpty) {
        final signature = _computeSignature(body, webhook.secret!);
        headers['X-Webhook-Signature'] = 'sha256=$signature';
      }

      final response = await _httpClient
          .post(
            Uri.parse(webhook.url),
            headers: headers,
            body: body,
          )
          .timeout(deliveryTimeout);

      statusCode = response.statusCode;

      if (statusCode >= 200 && statusCode < 300) {
        // Success - reset failure count
        await metadata.updateWebhook(
          webhook.copyWith(
            lastTriggeredAt: DateTime.now(),
            failureCount: 0,
          ),
        );

        Logger.info(
          'Webhook delivered successfully',
          component: 'webhook',
          metadata: {
            'webhookId': webhook.id,
            'event': payload.eventType,
            'statusCode': statusCode,
          },
        );
      } else {
        // Server returned error status
        error = 'Server returned status $statusCode';
        await _handleFailure(webhook, error);
      }
    } catch (e) {
      error = e.toString();
      await _handleFailure(webhook, error);
      Logger.warn(
        'Webhook delivery failed',
        component: 'webhook',
        metadata: {
          'webhookId': webhook.id,
          'event': payload.eventType,
          'error': error,
        },
      );
    }

    // Log the delivery attempt
    final duration = DateTime.now().difference(startTime);
    final delivery = WebhookDelivery(
      id: _uuid.v4(),
      webhookId: webhook.id,
      eventType: payload.eventType,
      payload: payload.toJson(),
      statusCode: statusCode,
      success: error == null,
      error: error,
      duration: duration,
      deliveredAt: DateTime.now(),
    );

    await metadata.logWebhookDelivery(delivery);
  }

  /// Handle a webhook delivery failure.
  Future<void> _handleFailure(Webhook webhook, String error) async {
    final newFailureCount = webhook.failureCount + 1;
    final shouldDisable = newFailureCount >= maxFailures;

    await metadata.updateWebhook(
      webhook.copyWith(
        lastTriggeredAt: DateTime.now(),
        failureCount: newFailureCount,
        isActive: shouldDisable ? false : webhook.isActive,
      ),
    );

    if (shouldDisable) {
      Logger.warn(
        'Webhook disabled after $maxFailures consecutive failures',
        component: 'webhook',
        metadata: {'webhookId': webhook.id, 'url': webhook.url},
      );
    }
  }

  /// Compute HMAC-SHA256 signature for a payload.
  String _computeSignature(String payload, String secret) {
    final key = utf8.encode(secret);
    final bytes = utf8.encode(payload);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(bytes);
    return digest.toString();
  }
}

/// Extension for triggering webhooks from handlers.
extension WebhookTriggers on WebhookService {
  /// Trigger webhook for package published event.
  Future<void> onPackagePublished({
    required String packageName,
    required String version,
    String? publisherEmail,
  }) async {
    await triggerEvent(
      eventType: WebhookEventType.packagePublished,
      data: {
        'package': packageName,
        'version': version,
        if (publisherEmail != null) 'publisher_email': publisherEmail,
      },
    );
  }

  /// Trigger webhook for package deleted event.
  Future<void> onPackageDeleted({
    required String packageName,
    String? deletedBy,
  }) async {
    await triggerEvent(
      eventType: WebhookEventType.packageDeleted,
      data: {
        'package': packageName,
        if (deletedBy != null) 'deleted_by': deletedBy,
      },
    );
  }

  /// Trigger webhook for version deleted event.
  Future<void> onVersionDeleted({
    required String packageName,
    required String version,
    String? deletedBy,
  }) async {
    await triggerEvent(
      eventType: WebhookEventType.versionDeleted,
      data: {
        'package': packageName,
        'version': version,
        if (deletedBy != null) 'deleted_by': deletedBy,
      },
    );
  }

  /// Trigger webhook for package discontinued event.
  Future<void> onPackageDiscontinued({
    required String packageName,
    String? replacedBy,
  }) async {
    await triggerEvent(
      eventType: WebhookEventType.packageDiscontinued,
      data: {
        'package': packageName,
        if (replacedBy != null) 'replaced_by': replacedBy,
      },
    );
  }

  /// Trigger webhook for package reactivated event.
  Future<void> onPackageReactivated({
    required String packageName,
  }) async {
    await triggerEvent(
      eventType: WebhookEventType.packageReactivated,
      data: {'package': packageName},
    );
  }

  /// Trigger webhook for user registered event.
  Future<void> onUserRegistered({
    required String email,
  }) async {
    await triggerEvent(
      eventType: WebhookEventType.userRegistered,
      data: {'email': email},
    );
  }

  /// Trigger webhook for cache cleared event.
  Future<void> onCacheCleared({
    String? packageName,
  }) async {
    await triggerEvent(
      eventType: WebhookEventType.cacheCleared,
      data: {
        if (packageName != null) 'package': packageName,
        'all': packageName == null,
      },
    );
  }
}
