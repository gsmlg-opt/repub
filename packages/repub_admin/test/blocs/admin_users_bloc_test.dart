import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repub_model/repub_model.dart' as model;

import 'package:repub_admin/blocs/admin_users/admin_users_bloc.dart';
import 'package:repub_admin/blocs/admin_users/admin_users_event.dart';
import 'package:repub_admin/blocs/admin_users/admin_users_state.dart';
import 'package:repub_admin/services/admin_api_client.dart';

// Mock classes
class MockAdminApiClient extends Mock implements AdminApiClient {}

void main() {
  group('AdminUsersBloc', () {
    late MockAdminApiClient mockApiClient;

    setUp(() {
      mockApiClient = MockAdminApiClient();
    });

    test('initial state is AdminUsersInitial', () {
      final bloc = AdminUsersBloc(apiClient: mockApiClient);
      expect(bloc.state, const AdminUsersInitial());
      bloc.close();
    });

    group('LoadAdminUsers', () {
      final testAdminUsers = [
        _createAdminUser('admin-1', 'admin'),
        _createAdminUser('admin-2', 'superuser'),
      ];

      blocTest<AdminUsersBloc, AdminUsersState>(
        'emits [AdminUsersLoading, AdminUsersLoaded] when LoadAdminUsers succeeds',
        build: () {
          when(() => mockApiClient.listAdminUsers())
              .thenAnswer((_) async => testAdminUsers);
          return AdminUsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadAdminUsers()),
        expect: () => [
          const AdminUsersLoading(),
          isA<AdminUsersLoaded>()
              .having((s) => s.adminUsers.length, 'admin users count', 2)
              .having(
                  (s) => s.adminUsers.first.username, 'first username', 'admin'),
        ],
      );

      blocTest<AdminUsersBloc, AdminUsersState>(
        'emits [AdminUsersLoading, AdminUsersError] when LoadAdminUsers fails',
        build: () {
          when(() => mockApiClient.listAdminUsers())
              .thenThrow(Exception('Network error'));
          return AdminUsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadAdminUsers()),
        expect: () => [
          const AdminUsersLoading(),
          isA<AdminUsersError>()
              .having((s) => s.message, 'message', contains('Failed to load')),
        ],
      );

      blocTest<AdminUsersBloc, AdminUsersState>(
        'handles empty admin users list',
        build: () {
          when(() => mockApiClient.listAdminUsers())
              .thenAnswer((_) async => <model.AdminUser>[]);
          return AdminUsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadAdminUsers()),
        expect: () => [
          const AdminUsersLoading(),
          isA<AdminUsersLoaded>()
              .having((s) => s.adminUsers.length, 'admin users count', 0),
        ],
      );
    });

    group('LoadAdminUserDetail', () {
      final testDetail = AdminUserDetail(
        adminUser: _createAdminUser('admin-1', 'admin'),
        recentLogins: [
          _createLoginHistory('login-1', true),
          _createLoginHistory('login-2', true),
        ],
      );

      blocTest<AdminUsersBloc, AdminUsersState>(
        'emits [AdminUserDetailLoading, AdminUserDetailLoaded] when LoadAdminUserDetail succeeds',
        build: () {
          when(() => mockApiClient.getAdminUser('admin-1'))
              .thenAnswer((_) async => testDetail);
          return AdminUsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadAdminUserDetail('admin-1')),
        expect: () => [
          const AdminUserDetailLoading('admin-1'),
          isA<AdminUserDetailLoaded>()
              .having((s) => s.adminUser.username, 'username', 'admin')
              .having((s) => s.loginHistory.length, 'login history count', 2),
        ],
      );

      blocTest<AdminUsersBloc, AdminUsersState>(
        'emits [AdminUserDetailLoading, AdminUsersError] when LoadAdminUserDetail fails',
        build: () {
          when(() => mockApiClient.getAdminUser('admin-1'))
              .thenThrow(AdminApiException(
                  statusCode: 404, message: 'Admin user not found'));
          return AdminUsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadAdminUserDetail('admin-1')),
        expect: () => [
          const AdminUserDetailLoading('admin-1'),
          isA<AdminUsersError>()
              .having(
                  (s) => s.message, 'message', contains('Failed to load')),
        ],
      );

      blocTest<AdminUsersBloc, AdminUsersState>(
        'handles admin user with no login history',
        build: () {
          when(() => mockApiClient.getAdminUser('admin-new'))
              .thenAnswer((_) async => AdminUserDetail(
                    adminUser: _createAdminUser('admin-new', 'newadmin'),
                    recentLogins: [],
                  ));
          return AdminUsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadAdminUserDetail('admin-new')),
        expect: () => [
          const AdminUserDetailLoading('admin-new'),
          isA<AdminUserDetailLoaded>()
              .having((s) => s.adminUser.username, 'username', 'newadmin')
              .having((s) => s.loginHistory, 'login history', isEmpty),
        ],
      );
    });

    group('LoadLoginHistory', () {
      final testLoginHistory = [
        _createLoginHistory('login-1', true),
        _createLoginHistory('login-2', false),
        _createLoginHistory('login-3', true),
      ];

      blocTest<AdminUsersBloc, AdminUsersState>(
        'emits [LoginHistoryLoading, LoginHistoryLoaded] when LoadLoginHistory succeeds',
        build: () {
          when(() => mockApiClient.getAdminLoginHistory('admin-1'))
              .thenAnswer((_) async => testLoginHistory);
          return AdminUsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadLoginHistory('admin-1')),
        expect: () => [
          const LoginHistoryLoading('admin-1'),
          isA<LoginHistoryLoaded>()
              .having((s) => s.adminUserId, 'admin user id', 'admin-1')
              .having((s) => s.loginHistory.length, 'login history count', 3),
        ],
      );

      blocTest<AdminUsersBloc, AdminUsersState>(
        'emits [LoginHistoryLoading, AdminUsersError] when LoadLoginHistory fails',
        build: () {
          when(() => mockApiClient.getAdminLoginHistory('admin-1'))
              .thenThrow(Exception('Database error'));
          return AdminUsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadLoginHistory('admin-1')),
        expect: () => [
          const LoginHistoryLoading('admin-1'),
          isA<AdminUsersError>()
              .having(
                  (s) => s.message, 'message', contains('Failed to load')),
        ],
      );

      blocTest<AdminUsersBloc, AdminUsersState>(
        'handles empty login history',
        build: () {
          when(() => mockApiClient.getAdminLoginHistory('admin-1'))
              .thenAnswer((_) async => <model.AdminLoginHistory>[]);
          return AdminUsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadLoginHistory('admin-1')),
        expect: () => [
          const LoginHistoryLoading('admin-1'),
          isA<LoginHistoryLoaded>()
              .having((s) => s.adminUserId, 'admin user id', 'admin-1')
              .having((s) => s.loginHistory, 'login history', isEmpty),
        ],
      );
    });
  });
}

// Helper functions to create test data

model.AdminUser _createAdminUser(String id, String username) {
  return model.AdminUser(
    id: id,
    username: username,
    passwordHash: 'hash',
    createdAt: DateTime.now(),
    isActive: true,
  );
}

model.AdminLoginHistory _createLoginHistory(String id, bool success) {
  return model.AdminLoginHistory(
    id: id,
    adminUserId: 'admin-1',
    loginAt: DateTime.now(),
    ipAddress: '192.168.1.1',
    userAgent: 'Mozilla/5.0',
    success: success,
  );
}
