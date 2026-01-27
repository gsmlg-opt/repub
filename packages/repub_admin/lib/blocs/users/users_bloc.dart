import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/admin_api_client.dart';
import '../../models/user_info.dart';
import 'users_event.dart';
import 'users_state.dart';

/// BLoC that manages users state and handles user events.
class UsersBloc extends Bloc<UsersEvent, UsersState> {
  final AdminApiClient _apiClient;

  UsersBloc({AdminApiClient? apiClient})
      : _apiClient = apiClient ?? AdminApiClient(),
        super(const UsersInitial()) {
    on<LoadUsers>(_onLoadUsers);
    on<SearchUsers>(_onSearchUsers);
    on<ActivateUser>(_onActivateUser);
    on<DeactivateUser>(_onDeactivateUser);
    on<DeleteUser>(_onDeleteUser);
    on<ViewUserTokens>(_onViewUserTokens);
  }

  Future<void> _onLoadUsers(
    LoadUsers event,
    Emitter<UsersState> emit,
  ) async {
    emit(const UsersLoading());
    try {
      final response = await _apiClient.listUsers(
        page: event.page,
        limit: event.limit,
      );

      // Convert from repub_model.User to our UserInfo model
      final users = response.users.map((user) {
        return UserInfo(
          id: user.id,
          email: user.email,
          createdAt: user.createdAt,
          isActive: true, // TODO: Add isActive field to backend User model
          tokenCount: 0, // TODO: Add token count from backend
          lastLoginAt: null, // TODO: Add last login tracking
        );
      }).toList();

      emit(UsersLoaded(
        users: users,
        total: response.total,
        page: response.page,
        limit: response.limit,
        searchQuery: event.search,
        activeOnly: event.activeOnly,
      ));
    } catch (e) {
      emit(UsersError('Failed to load users: $e'));
    }
  }

  Future<void> _onSearchUsers(
    SearchUsers event,
    Emitter<UsersState> emit,
  ) async {
    if (state is UsersLoaded) {
      final currentState = state as UsersLoaded;
      add(LoadUsers(
        page: 1, // Reset to first page on search
        limit: currentState.limit,
        search: event.query,
        activeOnly: currentState.activeOnly,
      ));
    }
  }

  Future<void> _onActivateUser(
    ActivateUser event,
    Emitter<UsersState> emit,
  ) async {
    emit(UserOperationInProgress('activating', event.userId));
    try {
      await _apiClient.updateUser(event.userId, isActive: true);
      emit(const UserOperationSuccess('User activated successfully'));

      // Reload users list
      if (state is UsersLoaded) {
        final currentState = state as UsersLoaded;
        add(LoadUsers(
          page: currentState.page,
          limit: currentState.limit,
          search: currentState.searchQuery,
          activeOnly: currentState.activeOnly,
        ));
      } else {
        add(const LoadUsers());
      }
    } catch (e) {
      emit(UserOperationError('Failed to activate user: $e'));
    }
  }

  Future<void> _onDeactivateUser(
    DeactivateUser event,
    Emitter<UsersState> emit,
  ) async {
    emit(UserOperationInProgress('deactivating', event.userId));
    try {
      await _apiClient.updateUser(event.userId, isActive: false);
      emit(const UserOperationSuccess('User deactivated successfully'));

      // Reload users list
      if (state is UsersLoaded) {
        final currentState = state as UsersLoaded;
        add(LoadUsers(
          page: currentState.page,
          limit: currentState.limit,
          search: currentState.searchQuery,
          activeOnly: currentState.activeOnly,
        ));
      } else {
        add(const LoadUsers());
      }
    } catch (e) {
      emit(UserOperationError('Failed to deactivate user: $e'));
    }
  }

  Future<void> _onDeleteUser(
    DeleteUser event,
    Emitter<UsersState> emit,
  ) async {
    emit(UserOperationInProgress('deleting', event.userId));
    try {
      await _apiClient.deleteUser(event.userId);
      emit(const UserOperationSuccess('User deleted successfully'));

      // Reload users list
      if (state is UsersLoaded) {
        final currentState = state as UsersLoaded;
        add(LoadUsers(
          page: currentState.page,
          limit: currentState.limit,
          search: currentState.searchQuery,
          activeOnly: currentState.activeOnly,
        ));
      } else {
        add(const LoadUsers());
      }
    } catch (e) {
      emit(UserOperationError('Failed to delete user: $e'));
    }
  }

  Future<void> _onViewUserTokens(
    ViewUserTokens event,
    Emitter<UsersState> emit,
  ) async {
    try {
      // TODO: Implement getUserTokens API method
      // For now, return empty list
      emit(UserTokensLoaded(
        userId: event.userId,
        tokens: const [],
      ));
    } catch (e) {
      emit(UserOperationError('Failed to load user tokens: $e'));
    }
  }
}
