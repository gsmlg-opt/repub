import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:repub_admin/screens/login_screen.dart';
import 'package:repub_admin/services/auth_service.dart';

// Mock classes
class MockAuthBloc extends Mock implements AuthBloc {}

class FakeAuthEvent extends Fake implements AuthEvent {}

class FakeAuthState extends Fake implements AuthState {}

void main() {
  late MockAuthBloc mockAuthBloc;

  setUpAll(() {
    registerFallbackValue(FakeAuthEvent());
    registerFallbackValue(FakeAuthState());
  });

  setUp(() {
    mockAuthBloc = MockAuthBloc();
    when(() => mockAuthBloc.stream)
        .thenAnswer((_) => Stream.value(const AuthUnauthenticated()));
    when(() => mockAuthBloc.state).thenReturn(const AuthUnauthenticated());
  });

  Widget createTestWidget() {
    return MaterialApp(
      home: BlocProvider<AuthBloc>.value(
        value: mockAuthBloc,
        child: const LoginScreen(),
      ),
    );
  }

  group('LoginScreen', () {
    testWidgets('renders login form elements', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Check for title
      expect(find.text('Repub Admin'), findsOneWidget);

      // Check for form fields
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.text('Username'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);

      // Check for login button
      expect(find.text('Login'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);

      // Check for icons
      expect(find.byIcon(Icons.admin_panel_settings), findsOneWidget);
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('shows validation error when username is empty', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Tap login without entering anything
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Expect validation error for username
      expect(find.text('Please enter your username'), findsOneWidget);
    });

    testWidgets('shows validation error when password is empty', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Enter username only
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'admin',
      );
      await tester.tap(find.text('Login'));
      await tester.pumpAndSettle();

      // Expect validation error for password
      expect(find.text('Please enter your password'), findsOneWidget);
    });

    testWidgets('dispatches login event with valid credentials', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Enter credentials
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        'admin',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );

      // Tap login
      await tester.tap(find.text('Login'));
      await tester.pump();

      // Verify event was dispatched
      verify(() => mockAuthBloc.add(any(
            that: isA<AuthLoginRequested>()
                .having((e) => e.username, 'username', 'admin')
                .having((e) => e.password, 'password', 'password123'),
          ))).called(1);
    });

    testWidgets('shows loading indicator when authentication is in progress',
        (tester) async {
      when(() => mockAuthBloc.state).thenReturn(const AuthLoading());
      when(() => mockAuthBloc.stream)
          .thenAnswer((_) => Stream.value(const AuthLoading()));

      await tester.pumpWidget(createTestWidget());

      // Check for loading indicator in button
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Button should be disabled
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('disables form fields during loading', (tester) async {
      when(() => mockAuthBloc.state).thenReturn(const AuthLoading());
      when(() => mockAuthBloc.stream)
          .thenAnswer((_) => Stream.value(const AuthLoading()));

      await tester.pumpWidget(createTestWidget());

      // Form fields should be disabled
      final textFields = tester.widgetList<TextFormField>(
        find.byType(TextFormField),
      );

      for (final field in textFields) {
        expect(field.enabled, isFalse);
      }
    });

    testWidgets('shows error snackbar on authentication failure',
        (tester) async {
      final controller = StreamController<AuthState>.broadcast();
      when(() => mockAuthBloc.state).thenReturn(const AuthUnauthenticated());
      when(() => mockAuthBloc.stream).thenAnswer((_) => controller.stream);

      await tester.pumpWidget(createTestWidget());

      // Emit auth error
      controller.add(const AuthError('Invalid credentials'));
      await tester.pump();

      // Check for snackbar with error message
      expect(find.text('Invalid credentials'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SnackBar &&
              (widget.backgroundColor == Colors.red ||
                  widget.backgroundColor?.value == Colors.red.value),
        ),
        findsOneWidget,
      );

      await controller.close();
    });

    testWidgets('trims whitespace from username', (tester) async {
      await tester.pumpWidget(createTestWidget());

      // Enter credentials with whitespace
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Username'),
        '  admin  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );

      await tester.tap(find.text('Login'));
      await tester.pump();

      // Verify trimmed username was sent
      verify(() => mockAuthBloc.add(any(
            that: isA<AuthLoginRequested>()
                .having((e) => e.username, 'username', 'admin'),
          ))).called(1);
    });
  });
}
