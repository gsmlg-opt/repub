import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repub_model/repub_model.dart' as model;

import 'package:repub_admin/blocs/users/users_bloc.dart';
import 'package:repub_admin/blocs/users/users_event.dart';
import 'package:repub_admin/blocs/users/users_state.dart';
import 'package:repub_admin/services/admin_api_client.dart';

// Mock classes
class MockAdminApiClient extends Mock implements AdminApiClient {}

void main() {
  group('UsersBloc', () {
    late MockAdminApiClient mockApiClient;

    setUp(() {
      mockApiClient = MockAdminApiClient();
    });

    test('initial state is UsersInitial', () {
      final bloc = UsersBloc(apiClient: mockApiClient);
      expect(bloc.state, const UsersInitial());
      bloc.close();
    });

    group('LoadUsers', () {
      final testUsers = _createTestUserListResponse([
        _createUser('user-1', 'user1@example.com'),
        _createUser('user-2', 'user2@example.com'),
      ]);

      blocTest<UsersBloc, UsersState>(
        'emits [UsersLoading, UsersLoaded] when LoadUsers succeeds',
        build: () {
          when(() => mockApiClient.listUsers(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => testUsers);
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadUsers()),
        expect: () => [
          const UsersLoading(),
          isA<UsersLoaded>()
              .having((s) => s.users.length, 'users count', 2)
              .having((s) => s.total, 'total', 2)
              .having((s) => s.page, 'page', 1),
        ],
      );

      blocTest<UsersBloc, UsersState>(
        'emits [UsersLoading, UsersError] when LoadUsers fails',
        build: () {
          when(() => mockApiClient.listUsers(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenThrow(Exception('Network error'));
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadUsers()),
        expect: () => [
          const UsersLoading(),
          isA<UsersError>()
              .having((s) => s.message, 'message', contains('Network error')),
        ],
      );

      blocTest<UsersBloc, UsersState>(
        'passes page and limit parameters correctly',
        build: () {
          when(() => mockApiClient.listUsers(
                page: 3,
                limit: 15,
              )).thenAnswer((_) async => testUsers);
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadUsers(page: 3, limit: 15)),
        verify: (_) {
          verify(() => mockApiClient.listUsers(
                page: 3,
                limit: 15,
              )).called(1);
        },
      );
    });

    group('ActivateUser', () {
      blocTest<UsersBloc, UsersState>(
        'emits [UserOperationInProgress, UserOperationSuccess, ...] when activate succeeds',
        build: () {
          when(() => mockApiClient.updateUser('user-1', isActive: true))
              .thenAnswer((_) async => _createUser('user-1', 'user@test.com'));
          when(() => mockApiClient.listUsers(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => _createTestUserListResponse([]));
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const ActivateUser('user-1')),
        expect: () => [
          const UserOperationInProgress('activating', 'user-1'),
          const UserOperationSuccess('User activated successfully'),
          const UsersLoading(),
          isA<UsersLoaded>(),
        ],
      );

      blocTest<UsersBloc, UsersState>(
        'emits error when activate fails',
        build: () {
          when(() => mockApiClient.updateUser('user-1', isActive: true))
              .thenThrow(AdminApiException(
                  statusCode: 404, message: 'User not found'));
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const ActivateUser('user-1')),
        expect: () => [
          const UserOperationInProgress('activating', 'user-1'),
          isA<UserOperationError>()
              .having((s) => s.message, 'message', contains('Failed')),
        ],
      );
    });

    group('DeactivateUser', () {
      blocTest<UsersBloc, UsersState>(
        'emits [UserOperationInProgress, UserOperationSuccess, ...] when deactivate succeeds',
        build: () {
          when(() => mockApiClient.updateUser('user-2', isActive: false))
              .thenAnswer((_) async => _createUser('user-2', 'user@test.com'));
          when(() => mockApiClient.listUsers(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => _createTestUserListResponse([]));
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const DeactivateUser('user-2')),
        expect: () => [
          const UserOperationInProgress('deactivating', 'user-2'),
          const UserOperationSuccess('User deactivated successfully'),
          const UsersLoading(),
          isA<UsersLoaded>(),
        ],
      );
    });

    group('DeleteUser', () {
      blocTest<UsersBloc, UsersState>(
        'emits [UserOperationInProgress, UserOperationSuccess, ...] when delete succeeds',
        build: () {
          when(() => mockApiClient.deleteUser('user-3'))
              .thenAnswer((_) async {});
          when(() => mockApiClient.listUsers(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => _createTestUserListResponse([]));
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const DeleteUser('user-3')),
        expect: () => [
          const UserOperationInProgress('deleting', 'user-3'),
          const UserOperationSuccess('User deleted successfully'),
          const UsersLoading(),
          isA<UsersLoaded>(),
        ],
      );

      blocTest<UsersBloc, UsersState>(
        'emits error when delete fails',
        build: () {
          when(() => mockApiClient.deleteUser('user-3')).thenThrow(
              AdminApiException(
                  statusCode: 403, message: 'Cannot delete admin'));
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const DeleteUser('user-3')),
        expect: () => [
          const UserOperationInProgress('deleting', 'user-3'),
          isA<UserOperationError>()
              .having((s) => s.message, 'message', contains('Failed')),
        ],
      );
    });

    group('ViewUserTokens', () {
      blocTest<UsersBloc, UsersState>(
        'emits UserTokensLoaded when view tokens succeeds',
        build: () {
          when(() => mockApiClient.getUserTokens('user-1'))
              .thenAnswer((_) async => [
                    UserToken(
                      label: 'Token 1',
                      scopes: ['read:all'],
                      createdAt: DateTime.now(),
                    ),
                  ]);
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const ViewUserTokens('user-1')),
        expect: () => [
          isA<UserTokensLoaded>()
              .having((s) => s.userId, 'userId', 'user-1')
              .having((s) => s.tokens.length, 'tokens count', 1)
              .having(
                  (s) => s.tokens.first.label, 'first token label', 'Token 1'),
        ],
      );

      blocTest<UsersBloc, UsersState>(
        'emits error when view tokens fails',
        build: () {
          when(() => mockApiClient.getUserTokens('user-1')).thenThrow(
              AdminApiException(statusCode: 404, message: 'User not found'));
          return UsersBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const ViewUserTokens('user-1')),
        expect: () => [
          isA<UserOperationError>()
              .having((s) => s.message, 'message', contains('Failed')),
        ],
      );
    });

    group('SearchUsers', () {
      final testUsers = _createTestUserListResponse([
        _createUser('user-1', 'search@example.com'),
      ]);

      blocTest<UsersBloc, UsersState>(
        'triggers LoadUsers with search query when in loaded state',
        build: () {
          when(() => mockApiClient.listUsers(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => testUsers);
          return UsersBloc(apiClient: mockApiClient);
        },
        seed: () => UsersLoaded(
          users: const [],
          total: 0,
          page: 1,
          limit: 20,
        ),
        act: (bloc) => bloc.add(const SearchUsers('test')),
        verify: (_) {
          verify(() => mockApiClient.listUsers(
                page: 1,
                limit: 20,
              )).called(1);
        },
      );
    });
  });
}

// Helper functions to create test data

model.User _createUser(String id, String email) {
  return model.User(
    id: id,
    email: email,
    passwordHash: 'hash',
    createdAt: DateTime.now(),
  );
}

UserListResponse _createTestUserListResponse(List<model.User> users) {
  return UserListResponse(
    users: users,
    total: users.length,
    page: 1,
    limit: 20,
  );
}
