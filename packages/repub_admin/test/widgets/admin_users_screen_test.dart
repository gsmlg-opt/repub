import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:repub_admin/blocs/admin_users/admin_users_bloc.dart';
import 'package:repub_admin/blocs/admin_users/admin_users_event.dart';
import 'package:repub_admin/blocs/admin_users/admin_users_state.dart';
import 'package:repub_admin/models/admin_user_info.dart';
import 'package:repub_admin/screens/admin_users_screen.dart';
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
        child: const Scaffold(body: AdminUsersScreen()),
      ),
    );
  }

  Future<void> setLargeScreenSize(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  List<AdminUserInfo> createTestAdminUsers() {
    return [
      AdminUserInfo(
        id: 'admin-1',
        username: 'superadmin',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
        lastLoginAt: DateTime.now().subtract(const Duration(hours: 1)),
        loginCount: 50,
      ),
      AdminUserInfo(
        id: 'admin-2',
        username: 'devops',
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
        lastLoginAt: DateTime.now().subtract(const Duration(days: 2)),
        loginCount: 10,
      ),
    ];
  }

  group('AdminUsersScreen', () {
    testWidgets('triggers LoadAdminUsers on init', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state)
          .thenReturn(const AdminUsersInitial());
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(const AdminUsersInitial()),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      verify(() => mockAdminUsersBloc.add(const LoadAdminUsers())).called(1);
    });

    testWidgets('shows loading indicator when state is AdminUsersLoading',
        (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state)
          .thenReturn(const AdminUsersLoading());
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(const AdminUsersLoading()),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays "Admin Users" title', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUsersLoaded(createTestAdminUsers()),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // findsWidgets because it appears in both header and sidebar
      expect(find.text('Admin Users'), findsWidgets);
    });

    testWidgets('displays admin users list when state is AdminUsersLoaded',
        (tester) async {
      await setLargeScreenSize(tester);
      final adminUsers = createTestAdminUsers();
      when(() => mockAdminUsersBloc.state)
          .thenReturn(AdminUsersLoaded(adminUsers));
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('superadmin'), findsOneWidget);
      expect(find.text('devops'), findsOneWidget);
    });

    testWidgets('displays admin count chip', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUsersLoaded(createTestAdminUsers()),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('2 admins'), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        const AdminUsersError('Failed to load admin users'),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('shows empty state when no admin users', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        const AdminUsersLoaded([]),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('No admin users'), findsOneWidget);
    });

    testWidgets('displays info banner about CLI management', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUsersLoaded(createTestAdminUsers()),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(
        find.text('Admin users can only be managed via CLI'),
        findsOneWidget,
      );
    });

    testWidgets('displays refresh button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUsersLoaded(createTestAdminUsers()),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('displays login count for each admin', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUsersLoaded(createTestAdminUsers()),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Login counts from test data
      expect(find.text('50'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('displays view details button for each admin', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockAdminUsersBloc.state).thenReturn(
        AdminUsersLoaded(createTestAdminUsers()),
      );
      when(() => mockAdminUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockAdminUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Each admin row should have a view details button
      expect(find.byIcon(Icons.visibility), findsNWidgets(2));
    });
  });
}
