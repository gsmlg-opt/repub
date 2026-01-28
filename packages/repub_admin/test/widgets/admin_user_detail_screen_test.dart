import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:repub_admin/blocs/admin_users/admin_users_bloc.dart';
import 'package:repub_admin/blocs/admin_users/admin_users_event.dart';
import 'package:repub_admin/blocs/admin_users/admin_users_state.dart';
import 'package:repub_admin/models/admin_user_info.dart';
import 'package:repub_admin/screens/admin_user_detail_screen.dart';
import 'package:repub_admin/services/auth_service.dart';
import 'package:repub_model/repub_model.dart';

// Mock classes
class MockAdminUsersBloc extends Mock implements AdminUsersBloc {}

class MockAuthBloc extends Mock implements AuthBloc {}

class FakeAdminUsersEvent extends Fake implements AdminUsersEvent {}

class FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late MockAdminUsersBloc mockAdminUsersBloc;
  late MockAuthBloc mockAuthBloc;
  const testAdminId = 'admin-123';

  setUpAll(() {
    registerFallbackValue(FakeAdminUsersEvent());
    registerFallbackValue(FakeAuthEvent());
  });

  setUp(() {
    mockAdminUsersBloc = MockAdminUsersBloc();
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
          BlocProvider<AdminUsersBloc>.value(value: mockAdminUsersBloc),
          BlocProvider<AuthBloc>.value(value: mockAuthBloc),
        ],
        child: const Scaffold(body: AdminUserDetailScreen(adminUserId: testAdminId)),
      ),
    );
  }

  Future<void> setLargeScreenSize(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  AdminUserInfo createTestAdminUser() {
    return AdminUserInfo(
      id: testAdminId,
      username: 'superadmin',
      createdAt: DateTime(2024, 1, 1, 10, 0),
      lastLoginAt: DateTime(2024, 6, 15, 14, 30),
      loginCount: 42,
    );
  }

  List<LoginAttempt> createTestLoginHistory() {
    return [
      LoginAttempt(
        id: 'login-1',
        adminUserId: testAdminId,
        timestamp: DateTime(2024, 6, 15, 14, 30),
        success: true,
        ipAddress: '192.168.1.100',
        userAgent: 'Mozilla/5.0 Chrome',
      ),
      LoginAttempt(
        id: 'login-2',
        adminUserId: testAdminId,
        timestamp: DateTime(2024, 6, 14, 10, 0),
        success: false,
        ipAddress: '10.0.0.50',
        userAgent: 'Mozilla/5.0 Firefox',
        failureReason: 'Invalid password',
      ),
      LoginAttempt(
        id: 'login-3',
        adminUserId: testAdminId,
        timestamp: DateTime(2024, 6, 13, 8, 0),
        success: true,
        ipAddress: '192.168.1.100',
        userAgent: 'Mozilla/5.0 Chrome',
      ),
      LoginAttempt(
        id: 'login-4',
        adminUserId: testAdminId,
        timestamp: DateTime(2024, 6, 12, 16, 0),
        success: false,
        ipAddress: '203.0.113.50',
        userAgent: 'Bot/1.0',
        failureReason: 'brute_force attempt detected', // isSuspicious detected from failureReason
      ),
    ];
  }

  group('AdminUserDetailScreen', () {
    testWidgets('triggers LoadAdminUserDetail on init', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(const AdminUsersInitial());
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(const AdminUsersInitial()),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      verify(() => mockAdminUsersBloc.add(const LoadAdminUserDetail(testAdminId))).called(1);
    });

    testWidgets('shows loading indicator when state is AdminUserDetailLoading',
        (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state)
          .thenReturn(const AdminUserDetailLoading(testAdminId));
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(const AdminUserDetailLoading(testAdminId)),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays username in header when loaded', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('superadmin'), findsWidgets);
    });

    testWidgets('displays user info card with avatar', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Check for CircleAvatar with initial
      expect(find.byType(CircleAvatar), findsWidgets);
      expect(find.text('S'), findsOneWidget); // First letter of 'superadmin'
    });

    testWidgets('displays Administrator badge', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Administrator'), findsOneWidget);
    });

    testWidgets('displays login statistics', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Login Statistics'), findsOneWidget);
      expect(find.text('Total Logins'), findsOneWidget);
      // "Successful", "Failed", "Suspicious" appear multiple times:
      // once in stats card labels, once in filter chips, once in history badges
      expect(find.text('Successful'), findsWidgets);
      expect(find.text('Failed'), findsWidgets);
      expect(find.text('Suspicious'), findsWidgets);
    });

    testWidgets('displays correct login stats values', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(), // 2 success, 1 failed, 1 suspicious
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('42'), findsOneWidget); // Total logins from admin user
      expect(find.text('2'), findsWidgets); // Successful logins from history
      expect(find.text('1'), findsWidgets); // Suspicious attempts
    });

    testWidgets('displays login history table', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Login History'), findsOneWidget);
      expect(find.byType(DataTable), findsOneWidget);
    });

    testWidgets('displays filter chips for login history', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byType(FilterChip), findsNWidgets(3));
      expect(find.text('All'), findsOneWidget);
      // 'Successful' appears both in stats card and filter chip
      // 'Failed' appears both in stats card and filter chip
    });

    testWidgets('displays success badge in login history', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Success'), findsNWidgets(2)); // 2 successful logins
    });

    testWidgets('displays suspicious badge in login history', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // findsWidgets because 'Suspicious' appears in stats card and in history
      expect(find.text('Suspicious'), findsWidgets);
    });

    testWidgets('displays back button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('displays refresh button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        const AdminUsersError('Failed to load admin user details'),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('displays empty history state when no login attempts',
        (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: const [],
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('No login attempts found'), findsOneWidget);
    });

    testWidgets('displays IP addresses in login history', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('192.168.1.100'), findsNWidgets(2));
      expect(find.text('10.0.0.50'), findsOneWidget);
      expect(find.text('203.0.113.50'), findsOneWidget);
    });

    testWidgets('displays user ID in info card', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUserDetailLoaded(
          adminUser: createTestAdminUser(),
          loginHistory: createTestLoginHistory(),
        ),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('User ID'), findsOneWidget);
      expect(find.text(testAdminId), findsWidgets);
    });
  });
}
