import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:repub_admin/blocs/dashboard/dashboard_bloc.dart';
import 'package:repub_admin/blocs/dashboard/dashboard_event.dart';
import 'package:repub_admin/blocs/dashboard/dashboard_state.dart';
import 'package:repub_admin/models/dashboard_stats.dart';
import 'package:repub_admin/screens/dashboard_screen.dart';
import 'package:repub_admin/services/auth_service.dart';
import 'package:repub_model/repub_model.dart';

// Mock classes
class MockDashboardBloc extends Mock implements DashboardBloc {}

class MockAuthBloc extends Mock implements AuthBloc {}

class FakeDashboardEvent extends Fake implements DashboardEvent {}

class FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late MockDashboardBloc mockDashboardBloc;
  late MockAuthBloc mockAuthBloc;

  setUpAll(() {
    registerFallbackValue(FakeDashboardEvent());
    registerFallbackValue(FakeAuthEvent());
  });

  setUp(() {
    mockDashboardBloc = MockDashboardBloc();
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
          BlocProvider<DashboardBloc>.value(value: mockDashboardBloc),
          BlocProvider<AuthBloc>.value(value: mockAuthBloc),
        ],
        child: const Scaffold(body: DashboardScreen()),
      ),
    );
  }

  DashboardStats createTestStats({
    int totalPackages = 50,
    int totalUsers = 100,
    int totalDownloads = 5000,
    int activeTokens = 25,
    List<RecentActivity>? recentActivity,
  }) {
    return DashboardStats(
      totalPackages: totalPackages,
      totalUsers: totalUsers,
      totalDownloads: totalDownloads,
      activeTokens: activeTokens,
      recentActivity: recentActivity ??
          [
            RecentActivity(
              id: '1',
              type: 'package_published',
              description: 'user@example.com published my_package 1.0.0',
              timestamp: DateTime.now(),
            ),
            RecentActivity(
              id: '2',
              type: 'user_registered',
              description: 'newuser@example.com registered',
              timestamp: DateTime.now().subtract(const Duration(hours: 1)),
            ),
          ],
      topPackages: [],
    );
  }

  group('DashboardScreen', () {
    testWidgets('shows loading indicator when loading', (tester) async {
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoading());
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoading()));

      await tester.pumpWidget(createTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays stats cards when loaded', (tester) async {
      final stats = createTestStats();
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoaded(stats));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoaded(stats)));

      await tester.pumpWidget(createTestWidget());

      // Check for dashboard title
      expect(find.text('Dashboard'), findsOneWidget);

      // Check for stat cards
      expect(find.text('Total Packages'), findsOneWidget);
      expect(find.text('50'), findsOneWidget);
      expect(find.text('Total Users'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('Total Downloads'), findsOneWidget);
      expect(find.text('5000'), findsOneWidget);
      expect(find.text('Active Tokens'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
    });

    testWidgets('displays recent activity section', (tester) async {
      final stats = createTestStats();
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoaded(stats));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoaded(stats)));

      await tester.pumpWidget(createTestWidget());

      // Check for recent activity section
      expect(find.text('Recent Activity'), findsOneWidget);

      // Check for activity entries
      expect(
          find.text('user@example.com published my_package 1.0.0'), findsOneWidget);
      expect(find.text('newuser@example.com registered'), findsOneWidget);
    });

    testWidgets('displays quick actions section', (tester) async {
      final stats = createTestStats();
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoaded(stats));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoaded(stats)));

      await tester.pumpWidget(createTestWidget());

      // Check for quick actions section
      expect(find.text('Quick Actions'), findsOneWidget);
      expect(find.text('Manage Local Packages'), findsOneWidget);
      expect(find.text('Manage Cached Packages'), findsOneWidget);
      expect(find.text('Manage Users'), findsOneWidget);
      expect(find.text('Site Configuration'), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      when(() => mockDashboardBloc.state)
          .thenReturn(DashboardError('Network error'));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardError('Network error')));

      await tester.pumpWidget(createTestWidget());

      // Check for error display
      expect(find.text('Failed to load dashboard'), findsOneWidget);
      expect(find.text('Network error'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('retry button dispatches LoadDashboard event', (tester) async {
      when(() => mockDashboardBloc.state)
          .thenReturn(DashboardError('Network error'));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardError('Network error')));

      await tester.pumpWidget(createTestWidget());

      // Tap retry button
      await tester.tap(find.text('Try Again'));
      await tester.pump();

      // Verify LoadDashboard was dispatched
      verify(() => mockDashboardBloc.add(any(that: isA<LoadDashboard>())))
          .called(greaterThan(0));
    });

    testWidgets('refresh button dispatches RefreshDashboard event',
        (tester) async {
      final stats = createTestStats();
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoaded(stats));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoaded(stats)));

      await tester.pumpWidget(createTestWidget());

      // Find and tap refresh button
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      // Verify RefreshDashboard was dispatched
      verify(() => mockDashboardBloc.add(any(that: isA<RefreshDashboard>())))
          .called(1);
    });

    testWidgets('shows correct icons for activity types', (tester) async {
      final stats = createTestStats(
        recentActivity: [
          RecentActivity(
            id: '1',
            type: 'package_published',
            description: 'Package published',
            timestamp: DateTime.now(),
          ),
          RecentActivity(
            id: '2',
            type: 'user_registered',
            description: 'User registered',
            timestamp: DateTime.now(),
          ),
          RecentActivity(
            id: '3',
            type: 'admin_login',
            description: 'Admin logged in',
            timestamp: DateTime.now(),
          ),
          RecentActivity(
            id: '4',
            type: 'package_deleted',
            description: 'Package deleted',
            timestamp: DateTime.now(),
          ),
        ],
      );
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoaded(stats));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoaded(stats)));

      await tester.pumpWidget(createTestWidget());

      // Check for activity icons
      expect(find.byIcon(Icons.upload), findsOneWidget);
      expect(find.byIcon(Icons.person_add), findsOneWidget);
      expect(find.byIcon(Icons.login), findsOneWidget);
      expect(find.byIcon(Icons.delete_forever), findsOneWidget);
    });

    testWidgets('hides recent activity section when empty', (tester) async {
      final stats = createTestStats(recentActivity: []);
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoaded(stats));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoaded(stats)));

      await tester.pumpWidget(createTestWidget());

      // Recent Activity section should not be shown
      expect(find.text('Recent Activity'), findsNothing);
    });

    testWidgets('dispatches LoadDashboard on build', (tester) async {
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoading());
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoading()));

      await tester.pumpWidget(createTestWidget());

      // Verify LoadDashboard was dispatched
      verify(() => mockDashboardBloc.add(any(that: isA<LoadDashboard>())))
          .called(1);
    });

    testWidgets('shows stat card icons', (tester) async {
      final stats = createTestStats();
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoaded(stats));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoaded(stats)));

      await tester.pumpWidget(createTestWidget());

      // Check for stat icons
      expect(find.byIcon(Icons.inventory), findsWidgets);
      expect(find.byIcon(Icons.people), findsWidgets);
      expect(find.byIcon(Icons.download), findsWidgets);
      expect(find.byIcon(Icons.key), findsOneWidget);
    });

    testWidgets('formats timestamp correctly for recent activity',
        (tester) async {
      final now = DateTime.now();
      final stats = createTestStats(
        recentActivity: [
          RecentActivity(
            id: '1',
            type: 'package_published',
            description: 'Just happened',
            timestamp: now,
          ),
        ],
      );
      when(() => mockDashboardBloc.state).thenReturn(DashboardLoaded(stats));
      when(() => mockDashboardBloc.stream)
          .thenAnswer((_) => Stream.value(DashboardLoaded(stats)));

      await tester.pumpWidget(createTestWidget());

      // Should show "Just now" for very recent activity
      expect(find.text('Just now'), findsOneWidget);
    });
  });
}
