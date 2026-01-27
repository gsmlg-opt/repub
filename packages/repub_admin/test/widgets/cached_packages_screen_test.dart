import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:repub_admin/blocs/packages/packages_bloc.dart';
import 'package:repub_admin/blocs/packages/packages_event.dart';
import 'package:repub_admin/blocs/packages/packages_state.dart';
import 'package:repub_admin/models/package_info.dart' as admin;
import 'package:repub_admin/screens/cached_packages_screen.dart';
import 'package:repub_admin/services/auth_service.dart';
import 'package:repub_model/repub_model.dart';

// Mock classes
class MockPackagesBloc extends Mock implements PackagesBloc {}

class MockAuthBloc extends Mock implements AuthBloc {}

class FakePackagesEvent extends Fake implements PackagesEvent {}

class FakeAuthEvent extends Fake implements AuthEvent {}

void main() {
  late MockPackagesBloc mockPackagesBloc;
  late MockAuthBloc mockAuthBloc;

  setUpAll(() {
    registerFallbackValue(FakePackagesEvent());
    registerFallbackValue(FakeAuthEvent());
  });

  setUp(() {
    mockPackagesBloc = MockPackagesBloc();
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
          BlocProvider<PackagesBloc>.value(value: mockPackagesBloc),
          BlocProvider<AuthBloc>.value(value: mockAuthBloc),
        ],
        child: const Scaffold(body: CachedPackagesScreen()),
      ),
    );
  }

  Future<void> setLargeScreenSize(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  List<admin.PackageInfo> createTestPackages() {
    return [
      admin.PackageInfo(
        name: 'http',
        latestVersion: '1.1.0',
        description: 'HTTP requests',
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        downloadCount: 1000,
        isDiscontinued: false,
        versions: ['1.0.0', '1.1.0'],
      ),
      admin.PackageInfo(
        name: 'provider',
        latestVersion: '6.0.5',
        description: 'State management',
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        downloadCount: 5000,
        isDiscontinued: false,
        versions: ['6.0.0', '6.0.5'],
      ),
    ];
  }

  group('CachedPackagesScreen', () {
    testWidgets('triggers LoadCachedPackages on init', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(const PackagesInitial());
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(const PackagesInitial()),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      verify(() => mockPackagesBloc.add(const LoadCachedPackages())).called(1);
    });

    testWidgets('shows loading indicator when state is PackagesLoading',
        (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state)
          .thenReturn(const PackagesLoading(PackageViewType.cached));
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(const PackagesLoading(PackageViewType.cached)),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays "Cached Packages" title', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(
        PackagesLoaded(
          packages: createTestPackages(),
          viewType: PackageViewType.cached,
          total: 2,
          page: 1,
          limit: 20,
        ),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // findsWidgets because "Cached Packages" appears in both header and sidebar nav
      expect(find.text('Cached Packages'), findsWidgets);
    });

    testWidgets('displays package list when state is PackagesLoaded',
        (tester) async {
      await setLargeScreenSize(tester);
      final packages = createTestPackages();
      when(() => mockPackagesBloc.state).thenReturn(
        PackagesLoaded(
          packages: packages,
          viewType: PackageViewType.cached,
          total: 2,
          page: 1,
          limit: 20,
        ),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('http'), findsOneWidget);
      expect(find.text('provider'), findsOneWidget);
    });

    testWidgets('shows pub.dev source indicator', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(
        PackagesLoaded(
          packages: createTestPackages(),
          viewType: PackageViewType.cached,
          total: 2,
          page: 1,
          limit: 20,
        ),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('pub.dev'), findsNWidgets(2));
    });

    testWidgets('shows error icon when state is PackagesError', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(
        const PackagesError('Failed to load cached packages'),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('shows empty state when no packages cached', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(
        const PackagesLoaded(
          packages: [],
          viewType: PackageViewType.cached,
          total: 0,
          page: 1,
          limit: 20,
        ),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('No cached packages'), findsOneWidget);
    });

    testWidgets('displays search field', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(
        PackagesLoaded(
          packages: createTestPackages(),
          viewType: PackageViewType.cached,
          total: 2,
          page: 1,
          limit: 20,
        ),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('displays refresh button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(
        PackagesLoaded(
          packages: createTestPackages(),
          viewType: PackageViewType.cached,
          total: 2,
          page: 1,
          limit: 20,
        ),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('displays Clear All Cache button', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(
        PackagesLoaded(
          packages: createTestPackages(),
          viewType: PackageViewType.cached,
          total: 2,
          page: 1,
          limit: 20,
        ),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Clear All Cache'), findsOneWidget);
    });

    testWidgets('shows operation in progress state', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(
        const PackageOperationInProgress('clearing_cache', 'http'),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Clearing cache for http...'), findsOneWidget);
    });

    testWidgets('shows empty search state when no results', (tester) async {
      await setLargeScreenSize(tester);
      when(() => mockPackagesBloc.state).thenReturn(
        const PackagesLoaded(
          packages: [],
          viewType: PackageViewType.cached,
          total: 0,
          page: 1,
          limit: 20,
          searchQuery: 'nonexistent',
        ),
      );
      when(() => mockPackagesBloc.stream).thenAnswer(
        (_) => Stream.value(mockPackagesBloc.state),
      );

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(
        find.text('No cached packages found matching "nonexistent"'),
        findsOneWidget,
      );
    });
  });
}
