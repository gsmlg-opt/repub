import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:repub_admin/blocs/dashboard/dashboard_bloc.dart';
import 'package:repub_admin/blocs/dashboard/dashboard_event.dart';
import 'package:repub_admin/blocs/dashboard/dashboard_state.dart';
import 'package:repub_admin/models/dashboard_stats.dart';
import 'package:repub_admin/services/admin_api_client.dart';

// Mock classes
class MockAdminApiClient extends Mock implements AdminApiClient {}

void main() {
  group('DashboardBloc', () {
    late MockAdminApiClient mockApiClient;
    late DashboardBloc dashboardBloc;

    setUp(() {
      mockApiClient = MockAdminApiClient();
      dashboardBloc = DashboardBloc(apiClient: mockApiClient);
    });

    tearDown(() {
      dashboardBloc.close();
    });

    test('initial state is DashboardInitial', () {
      expect(dashboardBloc.state, const DashboardInitial());
    });

    group('LoadDashboard', () {
      final testStatsData = _createTestDashboardStatsData();

      blocTest<DashboardBloc, DashboardState>(
        'emits [DashboardLoading, DashboardLoaded] when LoadDashboard succeeds',
        build: () {
          when(() => mockApiClient.getDashboardStats())
              .thenAnswer((_) async => testStatsData);
          return DashboardBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadDashboard()),
        expect: () => [
          const DashboardLoading(),
          isA<DashboardLoaded>()
              .having((s) => s.stats.totalPackages, 'totalPackages', 10)
              .having((s) => s.stats.totalUsers, 'totalUsers', 5)
              .having(
                  (s) => s.stats.recentActivity.length, 'activity count', 3),
        ],
      );

      blocTest<DashboardBloc, DashboardState>(
        'emits [DashboardLoading, DashboardError] when LoadDashboard fails',
        build: () {
          when(() => mockApiClient.getDashboardStats())
              .thenThrow(Exception('Network error'));
          return DashboardBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadDashboard()),
        expect: () => [
          const DashboardLoading(),
          isA<DashboardError>()
              .having((s) => s.message, 'message', contains('Network error')),
        ],
      );

      blocTest<DashboardBloc, DashboardState>(
        'handles empty activity list gracefully',
        build: () {
          when(() => mockApiClient.getDashboardStats())
              .thenAnswer((_) async => _createTestDashboardStatsData(
                    activities: [],
                  ));
          return DashboardBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadDashboard()),
        expect: () => [
          const DashboardLoading(),
          isA<DashboardLoaded>().having(
              (s) => s.stats.recentActivity.isEmpty, 'empty activities', true),
        ],
      );

      blocTest<DashboardBloc, DashboardState>(
        'parses activity types correctly',
        build: () {
          when(() => mockApiClient.getDashboardStats())
              .thenAnswer((_) async => testStatsData);
          return DashboardBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadDashboard()),
        expect: () => [
          const DashboardLoading(),
          isA<DashboardLoaded>()
              .having(
                (s) => s.stats.recentActivity[0].type,
                'first activity type',
                'package_published',
              )
              .having(
                (s) => s.stats.recentActivity[1].type,
                'second activity type',
                'user_registered',
              )
              .having(
                (s) => s.stats.recentActivity[2].type,
                'third activity type',
                'admin_login',
              ),
        ],
      );
    });

    group('RefreshDashboard', () {
      final testStatsData = _createTestDashboardStatsData();

      blocTest<DashboardBloc, DashboardState>(
        'calls API when RefreshDashboard is triggered and already loaded',
        build: () {
          // Return different data to verify API is called
          when(() => mockApiClient.getDashboardStats()).thenAnswer(
            (_) async => _createTestDashboardStatsData(totalPackages: 20),
          );
          return DashboardBloc(apiClient: mockApiClient);
        },
        seed: () => DashboardLoaded(DashboardStats.fromJson(testStatsData)),
        act: (bloc) => bloc.add(const RefreshDashboard()),
        verify: (_) {
          verify(() => mockApiClient.getDashboardStats()).called(1);
        },
      );

      blocTest<DashboardBloc, DashboardState>(
        'emits [DashboardError] when RefreshDashboard fails',
        build: () {
          when(() => mockApiClient.getDashboardStats())
              .thenThrow(AdminApiException(
            statusCode: 500,
            message: 'Server error',
          ));
          return DashboardBloc(apiClient: mockApiClient);
        },
        seed: () => DashboardLoaded(DashboardStats.fromJson(testStatsData)),
        act: (bloc) => bloc.add(const RefreshDashboard()),
        expect: () => [
          isA<DashboardError>()
              .having((s) => s.message, 'message', contains('refresh')),
        ],
      );

      blocTest<DashboardBloc, DashboardState>(
        'triggers LoadDashboard when not in loaded state',
        build: () {
          when(() => mockApiClient.getDashboardStats())
              .thenAnswer((_) async => testStatsData);
          return DashboardBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const RefreshDashboard()),
        expect: () => [
          const DashboardLoading(),
          isA<DashboardLoaded>(),
        ],
      );
    });

    group('Activity Feed Integration', () {
      blocTest<DashboardBloc, DashboardState>(
        'activity descriptions are correctly populated',
        build: () {
          when(() => mockApiClient.getDashboardStats())
              .thenAnswer((_) async => _createTestDashboardStatsData());
          return DashboardBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadDashboard()),
        expect: () => [
          const DashboardLoading(),
          isA<DashboardLoaded>().having(
            (s) => s.stats.recentActivity[0].description,
            'description',
            contains('published'),
          ),
        ],
      );

      blocTest<DashboardBloc, DashboardState>(
        'activity timestamps are correctly parsed',
        build: () {
          when(() => mockApiClient.getDashboardStats())
              .thenAnswer((_) async => _createTestDashboardStatsData());
          return DashboardBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadDashboard()),
        expect: () => [
          const DashboardLoading(),
          isA<DashboardLoaded>().having(
            (s) => s.stats.recentActivity[0].timestamp,
            'timestamp is DateTime',
            isA<DateTime>(),
          ),
        ],
      );
    });
  });
}

/// Creates test dashboard stats data matching the API response format.
Map<String, dynamic> _createTestDashboardStatsData({
  int totalPackages = 10,
  int totalUsers = 5,
  int totalDownloads = 100,
  int activeTokens = 3,
  List<Map<String, dynamic>>? activities,
}) {
  return {
    'total_packages': totalPackages,
    'total_users': totalUsers,
    'total_downloads': totalDownloads,
    'active_tokens': activeTokens,
    'recent_activity': activities ?? _createTestActivities(),
    'top_packages': <Map<String, dynamic>>[],
  };
}

/// Creates test activity data matching the API response format.
List<Map<String, dynamic>> _createTestActivities() {
  final now = DateTime.now();
  return [
    {
      'id': 'act-001',
      'type': 'package_published',
      'description': 'testuser published test_package 1.0.0',
      'timestamp': now.subtract(const Duration(minutes: 5)).toIso8601String(),
      'actor_email': 'testuser@example.com',
      'target_package': 'test_package',
    },
    {
      'id': 'act-002',
      'type': 'user_registered',
      'description': 'newuser@example.com registered',
      'timestamp': now.subtract(const Duration(hours: 2)).toIso8601String(),
      'actor_email': 'newuser@example.com',
      'target_package': null,
    },
    {
      'id': 'act-003',
      'type': 'admin_login',
      'description': 'admin logged in to admin panel',
      'timestamp': now.subtract(const Duration(days: 1)).toIso8601String(),
      'actor_email': null,
      'target_package': null,
    },
  ];
}
