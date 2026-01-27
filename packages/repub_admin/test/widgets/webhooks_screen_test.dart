import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:repub_admin/blocs/webhooks/webhooks_bloc.dart';
import 'package:repub_admin/blocs/webhooks/webhooks_event.dart';
import 'package:repub_admin/blocs/webhooks/webhooks_state.dart';
import 'package:repub_admin/models/webhook_info.dart';
import 'package:repub_admin/screens/webhooks_screen.dart';
import 'package:repub_admin/services/auth_service.dart';
import 'package:repub_model/repub_model.dart';

// Mock classes
class MockWebhooksBloc extends Mock implements WebhooksBloc {}

class MockAuthBloc extends Mock implements AuthBloc {}

class FakeWebhooksEvent extends Fake implements WebhooksEvent {}

class FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late MockWebhooksBloc mockWebhooksBloc;
  late MockAuthBloc mockAuthBloc;

  setUpAll(() {
    registerFallbackValue(FakeWebhooksEvent());
    registerFallbackValue(FakeAuthEvent());
  });

  setUp(() {
    mockWebhooksBloc = MockWebhooksBloc();
    mockAuthBloc = MockAuthBloc();

    // Setup auth bloc
    when(() => mockAuthBloc.state).thenReturn(AuthAuthenticated(
      AdminUser(
        id: 'admin-1',
        username: 'admin',
        passwordHash: 'hash',
        createdAt: DateTime.now(),
        isActive: true,
      ),
    ));
    when(() => mockAuthBloc.stream).thenAnswer(
      (_) => Stream.value(mockAuthBloc.state),
    );
  });

  Widget createTestWidget() {
    return MaterialApp(
      home: MultiBlocProvider(
        providers: [
          BlocProvider<WebhooksBloc>.value(value: mockWebhooksBloc),
          BlocProvider<AuthBloc>.value(value: mockAuthBloc),
        ],
        child: const Scaffold(body: WebhooksScreen()),
      ),
    );
  }

  Future<void> setLargeScreenSize(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  List<WebhookInfo> createTestWebhooks() {
    return [
      WebhookInfo(
        id: 'webhook-1',
        url: 'https://example.com/webhook',
        events: ['package.published', 'package.deleted'],
        isActive: true,
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
        lastTriggeredAt: DateTime.now().subtract(const Duration(hours: 1)),
        failureCount: 0,
      ),
      WebhookInfo(
        id: 'webhook-2',
        url: 'https://api.example.org/notify',
        events: ['*'],
        isActive: false,
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
        failureCount: 3,
      ),
    ];
  }

  group('WebhooksScreen', () {
    testWidgets('triggers LoadWebhooks on init', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(const WebhooksInitial());
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(const WebhooksInitial()),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      verify(() => mockWebhooksBloc.add(const LoadWebhooks())).called(1);
    });

    testWidgets('shows loading indicator when state is WebhooksLoading',
        (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(const WebhooksLoading());
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(const WebhooksLoading()),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays "Webhooks" title', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        WebhooksLoaded(createTestWebhooks()),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // findsWidgets because it appears in header and sidebar
      expect(find.text('Webhooks'), findsWidgets);
    });

    testWidgets('displays webhook list when state is WebhooksLoaded',
        (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        WebhooksLoaded(createTestWebhooks()),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('https://example.com/webhook'), findsOneWidget);
      expect(find.text('https://api.example.org/notify'), findsOneWidget);
    });

    testWidgets('shows Add Webhook button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        WebhooksLoaded(createTestWebhooks()),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Add Webhook'), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        const WebhooksError('Failed to load webhooks'),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('shows empty state when no webhooks', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        const WebhooksLoaded([]),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('No webhooks configured'), findsOneWidget);
      expect(find.text('Add Your First Webhook'), findsOneWidget);
    });

    testWidgets('displays info banner about webhook events', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        WebhooksLoaded(createTestWebhooks()),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Webhook Events'), findsOneWidget);
    });

    testWidgets('displays disabled badge for inactive webhook', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        WebhooksLoaded(createTestWebhooks()),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('displays failure count badge', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        WebhooksLoaded(createTestWebhooks()),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('3 failures'), findsOneWidget);
    });

    testWidgets('displays action buttons for each webhook', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        WebhooksLoaded(createTestWebhooks()),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Each webhook has: send test, enable/disable, history, edit, delete
      expect(find.byIcon(Icons.send), findsNWidgets(2)); // Send test
      expect(find.byIcon(Icons.history), findsNWidgets(2)); // View deliveries
      expect(find.byIcon(Icons.edit), findsNWidgets(2)); // Edit
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2)); // Delete
    });

    testWidgets('displays event chips', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockWebhooksBloc.state).thenReturn(
        WebhooksLoaded(createTestWebhooks()),
      );
      when(() => mockWebhooksBloc.stream).thenAnswer(
        (_) => Stream.value(mockWebhooksBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // First webhook has package.published and package.deleted events
      expect(find.text('Package Published'), findsOneWidget);
      expect(find.text('Package Deleted'), findsOneWidget);
      // Second webhook has wildcard
      expect(find.text('All Events'), findsOneWidget);
    });
  });
}
