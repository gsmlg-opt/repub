import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repub_model/repub_model.dart' show AdminUser;

import 'package:repub_admin/blocs/config/config_bloc.dart';
import 'package:repub_admin/blocs/config/config_event.dart';
import 'package:repub_admin/blocs/config/config_state.dart';
import 'package:repub_admin/screens/site_config_screen.dart';
import 'package:repub_admin/services/auth_service.dart';

// Mock classes
class MockConfigBloc extends Mock implements ConfigBloc {}

class MockAuthBloc extends Mock implements AuthBloc {}

class FakeConfigEvent extends Fake implements ConfigEvent {}

class FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late MockConfigBloc mockConfigBloc;
  late MockAuthBloc mockAuthBloc;

  setUpAll(() {
    registerFallbackValue(FakeConfigEvent());
    registerFallbackValue(FakeAuthEvent());
  });

  setUp(() {
    mockConfigBloc = MockConfigBloc();
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

  Widget createTestWidget({Size screenSize = const Size(1200, 800)}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ConfigBloc>.value(value: mockConfigBloc),
            BlocProvider<AuthBloc>.value(value: mockAuthBloc),
          ],
          child: SizedBox(
            width: screenSize.width,
            height: screenSize.height,
            child: const Scaffold(body: SiteConfigScreen()),
          ),
        ),
      ),
    );
  }

  group('SiteConfigScreen', () {
    testWidgets('shows loading indicator when loading', (tester) async {
      when(() => mockConfigBloc.state).thenReturn(const ConfigLoading());
      when(() => mockConfigBloc.stream)
          .thenAnswer((_) => Stream.value(const ConfigLoading()));

      await tester.pumpWidget(createTestWidget());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error state with retry button', (tester) async {
      when(() => mockConfigBloc.state)
          .thenReturn(const ConfigError('Failed to load config'));
      when(() => mockConfigBloc.stream).thenAnswer(
        (_) => Stream.value(const ConfigError('Failed to load config')),
      );

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Failed to load configuration'), findsOneWidget);
      expect(find.text('Failed to load config'), findsOneWidget);
      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('dispatches LoadConfig on init', (tester) async {
      when(() => mockConfigBloc.state).thenReturn(const ConfigLoading());
      when(() => mockConfigBloc.stream)
          .thenAnswer((_) => Stream.value(const ConfigLoading()));

      await tester.pumpWidget(createTestWidget());

      verify(() => mockConfigBloc.add(any(that: isA<LoadConfig>()))).called(1);
    });

    testWidgets('retry button dispatches LoadConfig', (tester) async {
      when(() => mockConfigBloc.state)
          .thenReturn(const ConfigError('Failed to load config'));
      when(() => mockConfigBloc.stream).thenAnswer(
        (_) => Stream.value(const ConfigError('Failed to load config')),
      );

      await tester.pumpWidget(createTestWidget());

      // Tap retry button
      await tester.tap(find.text('Try Again'));
      await tester.pump();

      // Verify LoadConfig was dispatched (once on init, once on retry)
      verify(() => mockConfigBloc.add(any(that: isA<LoadConfig>())))
          .called(greaterThan(1));
    });

    testWidgets('shows header with title', (tester) async {
      when(() => mockConfigBloc.state).thenReturn(const ConfigLoading());
      when(() => mockConfigBloc.stream)
          .thenAnswer((_) => Stream.value(const ConfigLoading()));

      await tester.pumpWidget(createTestWidget());

      expect(find.text('Site Configuration'), findsOneWidget);
    });
  });
}
