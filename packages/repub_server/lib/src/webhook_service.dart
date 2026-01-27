import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:uuid/uuid.dart';

import 'logger.dart';

/// Service for triggering webhooks on events.
class WebhookService {
  static const _uuid = Uuid();

  final MetadataStore metadata;
  final http.Client _httpClient;

  /// Maximum number of delivery attempts before disabling a webhook.
  static const maxFailures = 5;

  /// Timeout for webhook delivery requests.
  static const deliveryTimeout = Duration(seconds: 10);

  WebhookService({
    required this.metadata,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

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

      // Deliver to all webhooks concurrently
      await Future.wait(
        webhooks.map((webhook) => _deliver(webhook, payload)),
      );
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
