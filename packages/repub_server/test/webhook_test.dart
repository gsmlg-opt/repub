import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:repub_model/repub_model.dart';
import 'package:repub_server/src/webhook_service.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

void main() {
  group('WebhookService', () {
    late SqliteMetadataStore metadata;
    late WebhookService webhookService;
    late List<http.Request> capturedRequests;
    late http.Client mockClient;

    setUp(() async {
      metadata = SqliteMetadataStore.inMemory();
      await metadata.runMigrations();

      capturedRequests = [];
      mockClient = MockClient((request) async {
        capturedRequests.add(request);
        return http.Response('OK', 200);
      });

      webhookService = WebhookService(
        metadata: metadata,
        httpClient: mockClient,
      );
    });

    group('triggerEvent', () {
      test('triggers matching webhooks', () async {
        // Create a webhook for package.published events
        await metadata.createWebhook(
          url: 'https://example.com/webhook',
          events: ['package.published'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg', 'version': '1.0.0'},
        );

        // Give time for async delivery
        await Future.delayed(Duration(milliseconds: 100));

        expect(capturedRequests, hasLength(1));
        expect(capturedRequests.first.url.toString(),
            equals('https://example.com/webhook'));
      });

      test('does not trigger webhooks for non-matching events', () async {
        await metadata.createWebhook(
          url: 'https://example.com/webhook',
          events: ['package.deleted'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        expect(capturedRequests, isEmpty);
      });

      test('triggers webhooks with wildcard events', () async {
        await metadata.createWebhook(
          url: 'https://example.com/webhook',
          events: ['*'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        expect(capturedRequests, hasLength(1));
      });

      test('does not trigger inactive webhooks', () async {
        final webhook = await metadata.createWebhook(
          url: 'https://example.com/webhook',
          events: ['*'],
        );

        // Deactivate the webhook
        await metadata.updateWebhook(webhook.copyWith(isActive: false));

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        expect(capturedRequests, isEmpty);
      });

      test('includes correct headers', () async {
        await metadata.createWebhook(
          url: 'https://example.com/webhook',
          events: ['package.published'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        final request = capturedRequests.first;
        expect(request.headers['content-type'], equals('application/json'));
        expect(request.headers['x-webhook-event'], equals('package.published'));
        expect(request.headers['x-webhook-delivery'], isNotNull);
      });

      test('includes HMAC signature when secret is configured', () async {
        await metadata.createWebhook(
          url: 'https://example.com/webhook',
          secret: 'my-secret-key',
          events: ['package.published'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        final request = capturedRequests.first;
        expect(request.headers['x-webhook-signature'], startsWith('sha256='));

        // Verify signature is correct
        final body = request.body;
        final key = utf8.encode('my-secret-key');
        final bytes = utf8.encode(body);
        final hmac = Hmac(sha256, key);
        final expectedSignature = 'sha256=${hmac.convert(bytes)}';

        expect(
            request.headers['x-webhook-signature'], equals(expectedSignature));
      });

      test('sends correct payload format', () async {
        await metadata.createWebhook(
          url: 'https://example.com/webhook',
          events: ['package.published'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg', 'version': '1.0.0'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        final request = capturedRequests.first;
        final payload = jsonDecode(request.body) as Map<String, dynamic>;

        expect(payload['event'], equals('package.published'));
        expect(payload['timestamp'], isNotNull);
        expect(payload['data']['package'], equals('test_pkg'));
        expect(payload['data']['version'], equals('1.0.0'));
      });

      test('logs delivery on success', () async {
        await metadata.createWebhook(
          url: 'https://example.com/webhook',
          events: ['package.published'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        final webhooks = await metadata.listWebhooks();
        final deliveries =
            await metadata.getWebhookDeliveries(webhooks.first.id);

        expect(deliveries, hasLength(1));
        expect(deliveries.first.success, isTrue);
        expect(deliveries.first.statusCode, equals(200));
        expect(deliveries.first.eventType, equals('package.published'));
      });

      test('increments failure count on error', () async {
        final failingClient = MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        });

        final failingService = WebhookService(
          metadata: metadata,
          httpClient: failingClient,
        );

        final webhook = await metadata.createWebhook(
          url: 'https://example.com/webhook',
          events: ['package.published'],
        );

        await failingService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        final updated = await metadata.getWebhook(webhook.id);
        expect(updated!.failureCount, equals(1));
      });

      test('disables webhook after max failures', () async {
        final failingClient = MockClient((request) async {
          return http.Response('Error', 500);
        });

        final failingService = WebhookService(
          metadata: metadata,
          httpClient: failingClient,
        );

        final webhook = await metadata.createWebhook(
          url: 'https://example.com/webhook',
          events: ['package.published'],
        );

        // Simulate 5 failures (maxFailures)
        for (var i = 0; i < 5; i++) {
          await failingService.triggerEvent(
            eventType: 'package.published',
            data: {'package': 'test_pkg'},
          );
          await Future.delayed(Duration(milliseconds: 50));
        }

        final updated = await metadata.getWebhook(webhook.id);
        expect(updated!.isActive, isFalse);
        expect(updated.failureCount, equals(5));
      });

      test('triggers multiple webhooks concurrently', () async {
        await metadata.createWebhook(
          url: 'https://example1.com/webhook',
          events: ['package.published'],
        );
        await metadata.createWebhook(
          url: 'https://example2.com/webhook',
          events: ['package.published'],
        );
        await metadata.createWebhook(
          url: 'https://example3.com/webhook',
          events: ['package.published'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 200));

        expect(capturedRequests, hasLength(3));
      });
    });

    group('SSRF Protection', () {
      test('blocks localhost URLs', () async {
        // Create webhook via storage layer (bypasses handler validation)
        // This simulates a webhook created before SSRF protection was added
        final webhook = await metadata.createWebhook(
          url: 'http://localhost/webhook',
          events: ['*'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        // Should not make any HTTP requests
        expect(capturedRequests, isEmpty);

        // Webhook should be disabled
        final updated = await metadata.getWebhook(webhook.id);
        expect(updated!.isActive, isFalse);
      });

      test('blocks 127.0.0.1 URLs', () async {
        final webhook = await metadata.createWebhook(
          url: 'http://127.0.0.1:8080/webhook',
          events: ['*'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        expect(capturedRequests, isEmpty);

        final updated = await metadata.getWebhook(webhook.id);
        expect(updated!.isActive, isFalse);
      });

      test('blocks AWS metadata service IP (169.254.169.254)', () async {
        final webhook = await metadata.createWebhook(
          url: 'http://169.254.169.254/latest/meta-data/',
          events: ['*'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        expect(capturedRequests, isEmpty);

        final updated = await metadata.getWebhook(webhook.id);
        expect(updated!.isActive, isFalse);
      });

      test('blocks private network 10.x.x.x URLs', () async {
        final webhook = await metadata.createWebhook(
          url: 'http://10.0.0.1/internal',
          events: ['*'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        expect(capturedRequests, isEmpty);

        final updated = await metadata.getWebhook(webhook.id);
        expect(updated!.isActive, isFalse);
      });

      test('blocks private network 192.168.x.x URLs', () async {
        final webhook = await metadata.createWebhook(
          url: 'http://192.168.1.1/webhook',
          events: ['*'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        expect(capturedRequests, isEmpty);

        final updated = await metadata.getWebhook(webhook.id);
        expect(updated!.isActive, isFalse);
      });

      test('blocks private network 172.16-31.x.x URLs', () async {
        final webhook = await metadata.createWebhook(
          url: 'http://172.16.0.1/webhook',
          events: ['*'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        expect(capturedRequests, isEmpty);

        final updated = await metadata.getWebhook(webhook.id);
        expect(updated!.isActive, isFalse);
      });

      test('allows 172.15.x.x URLs (not private)', () async {
        await metadata.createWebhook(
          url: 'http://172.15.0.1/webhook',
          events: ['package.published'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        // Should make HTTP request since 172.15.x.x is not a private range
        expect(capturedRequests, hasLength(1));
      });

      test('logs delivery failure for blocked URLs', () async {
        final webhook = await metadata.createWebhook(
          url: 'http://localhost/webhook',
          events: ['*'],
        );

        await webhookService.triggerEvent(
          eventType: 'package.published',
          data: {'package': 'test_pkg'},
        );

        await Future.delayed(Duration(milliseconds: 100));

        // Check that delivery was logged with error
        final deliveries = await metadata.getWebhookDeliveries(webhook.id);
        expect(deliveries, hasLength(1));
        expect(deliveries.first.success, isFalse);
        expect(deliveries.first.error, contains('Blocked'));
        expect(deliveries.first.statusCode, equals(0));
      });
    });

    group('WebhookEventType', () {
      test('validates known event types', () {
        expect(WebhookEventType.isValid('package.published'), isTrue);
        expect(WebhookEventType.isValid('package.deleted'), isTrue);
        expect(WebhookEventType.isValid('user.registered'), isTrue);
        expect(WebhookEventType.isValid('*'), isTrue);
      });

      test('rejects unknown event types', () {
        expect(WebhookEventType.isValid('unknown.event'), isFalse);
        expect(WebhookEventType.isValid(''), isFalse);
        expect(WebhookEventType.isValid('package'), isFalse);
      });
    });

    group('WebhookTriggers extension', () {
      test('onPackagePublished sends correct event', () async {
        await metadata.createWebhook(url: 'https://example.com', events: ['*']);

        await webhookService.onPackagePublished(
          packageName: 'my_pkg',
          version: '2.0.0',
          publisherEmail: 'user@example.com',
        );

        await Future.delayed(Duration(milliseconds: 100));

        final payload =
            jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
        expect(payload['event'], equals('package.published'));
        expect(payload['data']['package'], equals('my_pkg'));
        expect(payload['data']['version'], equals('2.0.0'));
        expect(payload['data']['publisher_email'], equals('user@example.com'));
      });

      test('onPackageDeleted sends correct event', () async {
        await metadata.createWebhook(url: 'https://example.com', events: ['*']);

        await webhookService.onPackageDeleted(
          packageName: 'deleted_pkg',
          deletedBy: 'admin',
        );

        await Future.delayed(Duration(milliseconds: 100));

        final payload =
            jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
        expect(payload['event'], equals('package.deleted'));
        expect(payload['data']['package'], equals('deleted_pkg'));
        expect(payload['data']['deleted_by'], equals('admin'));
      });

      test('onUserRegistered sends correct event', () async {
        await metadata.createWebhook(url: 'https://example.com', events: ['*']);

        await webhookService.onUserRegistered(email: 'new@example.com');

        await Future.delayed(Duration(milliseconds: 100));

        final payload =
            jsonDecode(capturedRequests.first.body) as Map<String, dynamic>;
        expect(payload['event'], equals('user.registered'));
        expect(payload['data']['email'], equals('new@example.com'));
      });
    });
  });

  group('Webhook Model', () {
    test('shouldTrigger returns true for matching event', () {
      final webhook = Webhook(
        id: '1',
        url: 'https://example.com',
        events: ['package.published', 'package.deleted'],
        createdAt: DateTime.now(),
      );

      expect(webhook.shouldTrigger('package.published'), isTrue);
      expect(webhook.shouldTrigger('package.deleted'), isTrue);
      expect(webhook.shouldTrigger('user.registered'), isFalse);
    });

    test('shouldTrigger returns true for wildcard', () {
      final webhook = Webhook(
        id: '1',
        url: 'https://example.com',
        events: ['*'],
        createdAt: DateTime.now(),
      );

      expect(webhook.shouldTrigger('package.published'), isTrue);
      expect(webhook.shouldTrigger('any.event'), isTrue);
    });

    test('shouldTrigger returns false when inactive', () {
      final webhook = Webhook(
        id: '1',
        url: 'https://example.com',
        events: ['*'],
        isActive: false,
        createdAt: DateTime.now(),
      );

      expect(webhook.shouldTrigger('package.published'), isFalse);
    });

    test('toJson excludes secret', () {
      final webhook = Webhook(
        id: '1',
        url: 'https://example.com',
        secret: 'my-secret',
        events: ['*'],
        createdAt: DateTime.now(),
      );

      final json = webhook.toJson();
      expect(json.containsKey('secret'), isFalse);
    });

    test('copyWith creates modified copy', () {
      final webhook = Webhook(
        id: '1',
        url: 'https://example.com',
        events: ['*'],
        isActive: true,
        failureCount: 0,
        createdAt: DateTime.now(),
      );

      final updated = webhook.copyWith(
        isActive: false,
        failureCount: 3,
      );

      expect(updated.id, equals(webhook.id));
      expect(updated.url, equals(webhook.url));
      expect(updated.isActive, isFalse);
      expect(updated.failureCount, equals(3));
    });
  });
}
