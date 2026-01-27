import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:repub_admin/blocs/users/users_bloc.dart';
import 'package:repub_admin/blocs/users/users_event.dart';
import 'package:repub_admin/blocs/users/users_state.dart';
import 'package:repub_admin/models/user_info.dart';
import 'package:repub_admin/screens/users_screen.dart';
import 'package:repub_admin/services/auth_service.dart';
import 'package:repub_model/repub_model.dart';

// Mock classes
class MockUsersBloc extends Mock implements UsersBloc {}

class MockAuthBloc extends Mock implements AuthBloc {}

class FakeUsersEvent extends Fake implements UsersEvent {}

class FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late MockUsersBloc mockUsersBloc;
  late MockAuthBloc mockAuthBloc;

  setUpAll(() {
    registerFallbackValue(FakeUsersEvent());
    registerFallbackValue(FakeAuthEvent());
  });

  setUp(() {
    mockUsersBloc = MockUsersBloc();
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
          BlocProvider<UsersBloc>.value(value: mockUsersBloc),
          BlocProvider<AuthBloc>.value(value: mockAuthBloc),
        ],
        child: const Scaffold(body: UsersScreen()),
      ),
    );
  }

  Future<void> setLargeScreenSize(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  List<UserInfo> createTestUsers({int count = 5}) {
    return List.generate(
      count,
      (i) => UserInfo(
        id: 'user-$i',
        email: 'user$i@example.com',
        isActive: i % 2 == 0,
        createdAt: DateTime.now().subtract(Duration(days: i)),
        tokenCount: i,
      ),
    );
  }

  group('UsersScreen', () {
    testWidgets('shows loading indicator when loading', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockUsersBloc.state).thenReturn(const UsersLoading());
      when(() => mockUsersBloc.stream)
          .thenAnswer((_) => Stream.value(const UsersLoading()));

      await tester.pumpWidget(createTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays user list when loaded', (tester) async {
      await setLargeScreenSize(tester);
      final users = createTestUsers();
      when(() => mockUsersBloc.state).thenReturn(UsersLoaded(
        users: users,
        total: users.length,
        page: 1,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      // Check for header - there may be multiple due to sidebar
      expect(find.text('User Management'), findsWidgets);

      // Check for users in table
      expect(find.text('user0@example.com'), findsOneWidget);
      expect(find.text('user1@example.com'), findsOneWidget);
      expect(find.text('user2@example.com'), findsOneWidget);
    });

    testWidgets('shows total users count chip', (tester) async {
      await setLargeScreenSize(tester);
      final users = createTestUsers(count: 15);
      when(() => mockUsersBloc.state).thenReturn(UsersLoaded(
        users: users,
        total: 15,
        page: 1,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      expect(find.text('15 users'), findsOneWidget);
    });

    testWidgets('displays search field', (tester) async {
      await setLargeScreenSize(tester);
      final users = createTestUsers();
      when(() => mockUsersBloc.state).thenReturn(UsersLoaded(
        users: users,
        total: users.length,
        page: 1,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      expect(find.byIcon(Icons.search), findsOneWidget);
      expect(find.text('Search by email...'), findsOneWidget);
    });

    testWidgets('displays filter chips', (tester) async {
      await setLargeScreenSize(tester);
      final users = createTestUsers();
      when(() => mockUsersBloc.state).thenReturn(UsersLoaded(
        users: users,
        total: users.length,
        page: 1,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      // Look for FilterChip widgets with specific labels
      expect(find.byType(FilterChip), findsAtLeast(3));
      expect(find.text('All'), findsWidgets);
      expect(find.text('Active'), findsWidgets);
      expect(find.text('Inactive'), findsWidgets);
    });

    testWidgets('shows empty state when no users', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockUsersBloc.state).thenReturn(const UsersLoaded(
        users: [],
        total: 0,
        page: 1,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      expect(find.text('No users registered'), findsOneWidget);
      expect(find.text('Users who register will appear here'), findsOneWidget);
    });

    testWidgets('shows empty search state when no results', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockUsersBloc.state).thenReturn(const UsersLoaded(
        users: [],
        total: 0,
        page: 1,
        limit: 10,
        searchQuery: 'nonexistent',
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      expect(
          find.text('No users found matching "nonexistent"'), findsOneWidget);
      expect(find.text('Clear search'), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockUsersBloc.state)
          .thenReturn(const UsersError('Failed to load users'));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Failed to load users'), findsWidgets);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('shows active/inactive status badges', (tester) async {
      await setLargeScreenSize(tester);
      final users = createTestUsers(count: 2);
      when(() => mockUsersBloc.state).thenReturn(UsersLoaded(
        users: users,
        total: users.length,
        page: 1,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      // Active user (index 0)
      expect(find.text('Active'), findsWidgets);
      // Inactive user (index 1)
      expect(find.text('Inactive'), findsWidgets);
    });

    testWidgets('shows pagination controls', (tester) async {
      await setLargeScreenSize(tester);
      final users = createTestUsers(count: 10);
      when(() => mockUsersBloc.state).thenReturn(UsersLoaded(
        users: users,
        total: 25,
        page: 2,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('dispatches LoadUsers on init', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockUsersBloc.state).thenReturn(const UsersLoading());
      when(() => mockUsersBloc.stream)
          .thenAnswer((_) => Stream.value(const UsersLoading()));

      await tester.pumpWidget(createTestWidget());

      verify(() => mockUsersBloc.add(any(that: isA<LoadUsers>()))).called(1);
    });

    testWidgets('shows action buttons for each user', (tester) async {
      await setLargeScreenSize(tester);
      final users = createTestUsers(count: 1);
      when(() => mockUsersBloc.state).thenReturn(UsersLoaded(
        users: users,
        total: users.length,
        page: 1,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      // Check for action icons
      expect(find.byIcon(Icons.vpn_key), findsWidgets);
      expect(find.byIcon(Icons.block), findsWidgets);
      expect(find.byIcon(Icons.delete), findsWidgets);
    });

    testWidgets('shows token count for users', (tester) async {
      await setLargeScreenSize(tester);
      final users = [
        UserInfo(
          id: 'user-1',
          email: 'user1@example.com',
          isActive: true,
          createdAt: DateTime.now(),
          tokenCount: 5,
        ),
      ];
      when(() => mockUsersBloc.state).thenReturn(UsersLoaded(
        users: users,
        total: users.length,
        page: 1,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('refresh button dispatches LoadUsers', (tester) async {
      await setLargeScreenSize(tester);
      final users = createTestUsers();
      when(() => mockUsersBloc.state).thenReturn(UsersLoaded(
        users: users,
        total: users.length,
        page: 1,
        limit: 10,
      ));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      // Find and tap refresh button
      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();

      // LoadUsers should be dispatched (once on init, once on refresh)
      verify(() => mockUsersBloc.add(any(that: isA<LoadUsers>())))
          .called(greaterThan(1));
    });

    testWidgets('shows operation in progress state', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockUsersBloc.state)
          .thenReturn(const UserOperationInProgress('deleting', 'user-1'));
      when(() => mockUsersBloc.stream).thenAnswer(
        (_) => Stream.value(mockUsersBloc.state),
      );

      await tester.pumpWidget(createTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Deleting user...'), findsOneWidget);
    });
  });
}
