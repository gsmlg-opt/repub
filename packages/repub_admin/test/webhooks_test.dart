import 'dart:convert';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:repub_admin/blocs/webhooks/webhooks_bloc.dart';
import 'package:repub_admin/blocs/webhooks/webhooks_event.dart';
import 'package:repub_admin/blocs/webhooks/webhooks_state.dart';
import 'package:repub_admin/models/webhook_info.dart';
import 'package:repub_admin/services/admin_api_client.dart';

void main() {
  group('WebhookInfo', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'webhook-123',
        'url': 'https://example.com/webhook',
        'events': ['package.published', 'package.deleted'],
        'is_active': true,
        'created_at': '2024-01-01T00:00:00Z',
        'last_triggered_at': '2024-01-02T12:00:00Z',
        'failure_count': 2,
      };

      final webhook = WebhookInfo.fromJson(json);

      expect(webhook.id, equals('webhook-123'));
      expect(webhook.url, equals('https://example.com/webhook'));
      expect(webhook.events, equals(['package.published', 'package.deleted']));
      expect(webhook.isActive, isTrue);
      expect(webhook.createdAt, equals(DateTime.parse('2024-01-01T00:00:00Z')));
      expect(webhook.lastTriggeredAt,
          equals(DateTime.parse('2024-01-02T12:00:00Z')));
      expect(webhook.failureCount, equals(2));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'id': 'webhook-123',
        'url': 'https://example.com/webhook',
        'events': ['*'],
        'created_at': '2024-01-01T00:00:00Z',
      };

      final webhook = WebhookInfo.fromJson(json);

      expect(webhook.id, equals('webhook-123'));
      expect(webhook.isActive, isTrue); // defaults to true
      expect(webhook.lastTriggeredAt, isNull);
      expect(webhook.failureCount, equals(0)); // defaults to 0
    });

    test('toJson roundtrips correctly', () {
      final webhook = WebhookInfo(
        id: 'webhook-123',
        url: 'https://example.com/webhook',
        events: ['package.published'],
        isActive: true,
        createdAt: DateTime.parse('2024-01-01T00:00:00Z'),
        lastTriggeredAt: DateTime.parse('2024-01-02T12:00:00Z'),
        failureCount: 1,
      );

      final json = webhook.toJson();
      final restored = WebhookInfo.fromJson(json);

      expect(restored.id, equals(webhook.id));
      expect(restored.url, equals(webhook.url));
      expect(restored.events, equals(webhook.events));
      expect(restored.isActive, equals(webhook.isActive));
      expect(restored.failureCount, equals(webhook.failureCount));
    });

    test('copyWith creates modified copy', () {
      final original = WebhookInfo(
        id: 'webhook-123',
        url: 'https://example.com/webhook',
        events: ['package.published'],
        isActive: true,
        createdAt: DateTime.parse('2024-01-01T00:00:00Z'),
      );

      final modified = original.copyWith(
        url: 'https://new-url.com/webhook',
        isActive: false,
      );

      expect(modified.id, equals(original.id)); // unchanged
      expect(modified.url, equals('https://new-url.com/webhook'));
      expect(modified.isActive, isFalse);
      expect(modified.createdAt, equals(original.createdAt)); // unchanged
    });
  });

  group('WebhookDeliveryInfo', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'delivery-123',
        'webhook_id': 'webhook-456',
        'event_type': 'package.published',
        'status_code': 200,
        'success': true,
        'duration_ms': 150,
        'delivered_at': '2024-01-02T12:00:00Z',
      };

      final delivery = WebhookDeliveryInfo.fromJson(json);

      expect(delivery.id, equals('delivery-123'));
      expect(delivery.webhookId, equals('webhook-456'));
      expect(delivery.eventType, equals('package.published'));
      expect(delivery.statusCode, equals(200));
      expect(delivery.success, isTrue);
      expect(delivery.error, isNull);
      expect(delivery.durationMs, equals(150));
    });

    test('fromJson handles error field', () {
      final json = {
        'id': 'delivery-123',
        'webhook_id': 'webhook-456',
        'event_type': 'package.published',
        'status_code': 500,
        'success': false,
        'error': 'Internal server error',
        'duration_ms': 5000,
        'delivered_at': '2024-01-02T12:00:00Z',
      };

      final delivery = WebhookDeliveryInfo.fromJson(json);

      expect(delivery.success, isFalse);
      expect(delivery.error, equals('Internal server error'));
    });
  });

  group('WebhookEventTypes', () {
    test('displayName returns correct names', () {
      expect(WebhookEventTypes.displayName('package.published'),
          equals('Package Published'));
      expect(WebhookEventTypes.displayName('package.deleted'),
          equals('Package Deleted'));
      expect(WebhookEventTypes.displayName('version.deleted'),
          equals('Version Deleted'));
      expect(WebhookEventTypes.displayName('user.registered'),
          equals('User Registered'));
      expect(WebhookEventTypes.displayName('*'), equals('All Events'));
    });

    test('all contains expected events', () {
      expect(WebhookEventTypes.all, contains('package.published'));
      expect(WebhookEventTypes.all, contains('package.deleted'));
      expect(WebhookEventTypes.all, contains('version.deleted'));
      expect(WebhookEventTypes.all, contains('package.discontinued'));
      expect(WebhookEventTypes.all, contains('package.reactivated'));
      expect(WebhookEventTypes.all, contains('user.registered'));
      expect(WebhookEventTypes.all, contains('cache.cleared'));
    });
  });

  group('AdminApiClient webhook methods', () {
    late AdminApiClient apiClient;
    late List<http.Request> requests;

    setUp(() {
      requests = [];
    });

    AdminApiClient createClient(http.Response Function(http.Request) handler) {
      final mockClient = MockClient((request) async {
        requests.add(request);
        return handler(request);
      });
      return AdminApiClient.forTesting(
        baseUrl: 'http://localhost:4920',
        httpClient: mockClient,
      );
    }

    test('listWebhooks returns webhook list', () async {
      apiClient = createClient((request) {
        expect(request.url.path, equals('/admin/api/webhooks'));
        return http.Response(
          jsonEncode({
            'webhooks': [
              {
                'id': 'webhook-1',
                'url': 'https://example.com/hook1',
                'events': ['package.published'],
                'is_active': true,
                'created_at': '2024-01-01T00:00:00Z',
              },
              {
                'id': 'webhook-2',
                'url': 'https://example.com/hook2',
                'events': ['*'],
                'is_active': false,
                'created_at': '2024-01-02T00:00:00Z',
                'failure_count': 3,
              },
            ],
            'total': 2,
          }),
          200,
        );
      });

      final webhooks = await apiClient.listWebhooks();

      expect(webhooks.length, equals(2));
      expect(webhooks[0].id, equals('webhook-1'));
      expect(webhooks[0].isActive, isTrue);
      expect(webhooks[1].id, equals('webhook-2'));
      expect(webhooks[1].isActive, isFalse);
      expect(webhooks[1].failureCount, equals(3));
    });

    test('listWebhooks with activeOnly=true adds query param', () async {
      apiClient = createClient((request) {
        expect(request.url.queryParameters['active_only'], equals('true'));
        return http.Response(
          jsonEncode({'webhooks': [], 'total': 0}),
          200,
        );
      });

      await apiClient.listWebhooks(activeOnly: true);
    });

    test('createWebhook sends correct request', () async {
      apiClient = createClient((request) {
        expect(request.method, equals('POST'));
        expect(request.url.path, equals('/admin/api/webhooks'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['url'], equals('https://example.com/webhook'));
        expect(body['events'], equals(['package.published']));
        expect(body['secret'], equals('my-secret'));

        return http.Response(
          jsonEncode({
            'webhook': {
              'id': 'new-webhook-id',
              'url': 'https://example.com/webhook',
              'events': ['package.published'],
              'is_active': true,
              'created_at': '2024-01-03T00:00:00Z',
            },
          }),
          200,
        );
      });

      final webhook = await apiClient.createWebhook(
        url: 'https://example.com/webhook',
        events: ['package.published'],
        secret: 'my-secret',
      );

      expect(webhook.id, equals('new-webhook-id'));
      expect(webhook.url, equals('https://example.com/webhook'));
    });

    test('updateWebhook sends correct request', () async {
      apiClient = createClient((request) {
        expect(request.method, equals('PUT'));
        expect(request.url.path, equals('/admin/api/webhooks/webhook-123'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['url'], equals('https://new-url.com'));
        expect(body['is_active'], equals(false));

        return http.Response(
          jsonEncode({
            'webhook': {
              'id': 'webhook-123',
              'url': 'https://new-url.com',
              'events': ['*'],
              'is_active': false,
              'created_at': '2024-01-01T00:00:00Z',
            },
          }),
          200,
        );
      });

      final webhook = await apiClient.updateWebhook(
        'webhook-123',
        url: 'https://new-url.com',
        isActive: false,
      );

      expect(webhook.url, equals('https://new-url.com'));
      expect(webhook.isActive, isFalse);
    });

    test('deleteWebhook sends DELETE request', () async {
      apiClient = createClient((request) {
        expect(request.method, equals('DELETE'));
        expect(request.url.path, equals('/admin/api/webhooks/webhook-123'));
        return http.Response(jsonEncode({'success': true}), 200);
      });

      await apiClient.deleteWebhook('webhook-123');

      expect(requests.length, equals(1));
    });

    test('testWebhook sends POST request', () async {
      apiClient = createClient((request) {
        expect(request.method, equals('POST'));
        expect(
            request.url.path, equals('/admin/api/webhooks/webhook-123/test'));
        return http.Response(jsonEncode({'success': true}), 200);
      });

      final success = await apiClient.testWebhook('webhook-123');

      expect(success, isTrue);
    });

    test('getWebhookDeliveries returns delivery list', () async {
      apiClient = createClient((request) {
        expect(request.url.path,
            equals('/admin/api/webhooks/webhook-123/deliveries'));
        expect(request.url.queryParameters['limit'], equals('10'));

        return http.Response(
          jsonEncode({
            'deliveries': [
              {
                'id': 'delivery-1',
                'webhook_id': 'webhook-123',
                'event_type': 'package.published',
                'status_code': 200,
                'success': true,
                'duration_ms': 100,
                'delivered_at': '2024-01-02T00:00:00Z',
              },
              {
                'id': 'delivery-2',
                'webhook_id': 'webhook-123',
                'event_type': 'package.deleted',
                'status_code': 500,
                'success': false,
                'error': 'Server error',
                'duration_ms': 5000,
                'delivered_at': '2024-01-02T01:00:00Z',
              },
            ],
          }),
          200,
        );
      });

      final deliveries =
          await apiClient.getWebhookDeliveries('webhook-123', limit: 10);

      expect(deliveries.length, equals(2));
      expect(deliveries[0].success, isTrue);
      expect(deliveries[1].success, isFalse);
      expect(deliveries[1].error, equals('Server error'));
    });
  });

  group('WebhooksBloc', () {
    late AdminApiClient apiClient;

    AdminApiClient createMockClient(
        http.Response Function(http.Request) handler) {
      final mockClient = MockClient((request) async => handler(request));
      return AdminApiClient.forTesting(
        baseUrl: 'http://localhost:4920',
        httpClient: mockClient,
      );
    }

    blocTest<WebhooksBloc, WebhooksState>(
      'emits [WebhooksLoading, WebhooksLoaded] when LoadWebhooks succeeds',
      build: () {
        apiClient = createMockClient((request) {
          return http.Response(
            jsonEncode({
              'webhooks': [
                {
                  'id': 'webhook-1',
                  'url': 'https://example.com/hook1',
                  'events': ['*'],
                  'is_active': true,
                  'created_at': '2024-01-01T00:00:00Z',
                },
              ],
              'total': 1,
            }),
            200,
          );
        });
        return WebhooksBloc(apiClient: apiClient);
      },
      act: (bloc) => bloc.add(const LoadWebhooks()),
      expect: () => [
        isA<WebhooksLoading>(),
        isA<WebhooksLoaded>().having(
          (s) => s.webhooks.length,
          'webhook count',
          equals(1),
        ),
      ],
    );

    blocTest<WebhooksBloc, WebhooksState>(
      'emits [WebhooksLoading, WebhooksError] when LoadWebhooks fails',
      build: () {
        apiClient = createMockClient((request) {
          return http.Response('Server error', 500);
        });
        return WebhooksBloc(apiClient: apiClient);
      },
      act: (bloc) => bloc.add(const LoadWebhooks()),
      expect: () => [
        isA<WebhooksLoading>(),
        isA<WebhooksError>(),
      ],
    );

    blocTest<WebhooksBloc, WebhooksState>(
      'emits [WebhookCreating, WebhookCreated, ...] when CreateWebhook succeeds',
      build: () {
        apiClient = createMockClient((request) {
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({
                'webhook': {
                  'id': 'new-webhook',
                  'url': 'https://example.com/webhook',
                  'events': ['package.published'],
                  'is_active': true,
                  'created_at': '2024-01-01T00:00:00Z',
                },
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({'webhooks': [], 'total': 0}),
            200,
          );
        });
        return WebhooksBloc(apiClient: apiClient);
      },
      act: (bloc) => bloc.add(const CreateWebhook(
        url: 'https://example.com/webhook',
        events: ['package.published'],
      )),
      expect: () => [
        isA<WebhookCreating>(),
        isA<WebhookCreated>(),
        isA<WebhooksLoading>(),
        isA<WebhooksLoaded>(),
      ],
    );

    blocTest<WebhooksBloc, WebhooksState>(
      'emits [WebhookDeleting, WebhookDeleted, ...] when DeleteWebhook succeeds',
      build: () {
        apiClient = createMockClient((request) {
          if (request.method == 'DELETE') {
            return http.Response(jsonEncode({'success': true}), 200);
          }
          return http.Response(
            jsonEncode({'webhooks': [], 'total': 0}),
            200,
          );
        });
        return WebhooksBloc(apiClient: apiClient);
      },
      act: (bloc) => bloc.add(const DeleteWebhook('webhook-123')),
      expect: () => [
        isA<WebhookDeleting>(),
        isA<WebhookDeleted>(),
        isA<WebhooksLoading>(),
        isA<WebhooksLoaded>(),
      ],
    );

    blocTest<WebhooksBloc, WebhooksState>(
      'emits [WebhookTesting, WebhookTestCompleted] when TestWebhook succeeds',
      build: () {
        apiClient = createMockClient((request) {
          if (request.url.path.endsWith('/test')) {
            return http.Response(jsonEncode({'success': true}), 200);
          }
          return http.Response(
            jsonEncode({'webhooks': [], 'total': 0}),
            200,
          );
        });
        return WebhooksBloc(apiClient: apiClient);
      },
      act: (bloc) => bloc.add(const TestWebhook('webhook-123')),
      expect: () => [
        isA<WebhookTesting>(),
        isA<WebhookTestCompleted>().having(
          (s) => s.success,
          'success',
          isTrue,
        ),
        isA<WebhooksLoading>(),
        isA<WebhooksLoaded>(),
      ],
    );
  });
}
