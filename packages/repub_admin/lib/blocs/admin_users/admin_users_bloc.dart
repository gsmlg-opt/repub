import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/admin_api_client.dart';
import '../../models/admin_user_info.dart';
import 'admin_users_event.dart';
import 'admin_users_state.dart';

/// BLoC that manages admin users state and handles admin user events.
/// Admin users are read-only and can only be managed via CLI.
class AdminUsersBloc extends Bloc<AdminUsersEvent, AdminUsersState> {
  final AdminApiClient _apiClient;

  AdminUsersBloc({AdminApiClient? apiClient})
      : _apiClient = apiClient ?? AdminApiClient(),
        super(const AdminUsersInitial()) {
    on<LoadAdminUsers>(_onLoadAdminUsers);
    on<LoadAdminUserDetail>(_onLoadAdminUserDetail);
    on<LoadLoginHistory>(_onLoadLoginHistory);
  }

  Future<void> _onLoadAdminUsers(
    LoadAdminUsers event,
    Emitter<AdminUsersState> emit,
  ) async {
    emit(const AdminUsersLoading());
    try {
      final adminUsersList = await _apiClient.listAdminUsers();

      // Convert from repub_model.AdminUser to our AdminUserInfo model
      final adminUsers = adminUsersList.map((user) {
        return AdminUserInfo(
          id: user.id,
          username: user.username,
          createdAt: user.createdAt,
          lastLoginAt: null, // TODO: Add from backend
          loginCount: 0, // TODO: Add from backend
        );
      }).toList();

      emit(AdminUsersLoaded(adminUsers));
    } catch (e) {
      emit(AdminUsersError('Failed to load admin users: $e'));
    }
  }

  Future<void> _onLoadAdminUserDetail(
    LoadAdminUserDetail event,
    Emitter<AdminUsersState> emit,
  ) async {
    emit(AdminUserDetailLoading(event.adminUserId));
    try {
      final detail = await _apiClient.getAdminUser(event.adminUserId);

      // Convert to our models
      final adminUser = AdminUserInfo(
        id: detail.adminUser.id,
        username: detail.adminUser.username,
        createdAt: detail.adminUser.createdAt,
        lastLoginAt: null,
        loginCount: detail.recentLogins.length,
      );

      // Convert login history
      final loginHistory = detail.recentLogins.map((login) {
        return LoginAttempt(
          id: login.id,
          adminUserId: event.adminUserId,
          timestamp: login.loginAt,
          success: login.success,
          ipAddress: login.ipAddress,
          userAgent: login.userAgent,
          failureReason: null, // Not available in current model
        );
      }).toList();

      emit(AdminUserDetailLoaded(
        adminUser: adminUser,
        loginHistory: loginHistory,
      ));
    } catch (e) {
      emit(AdminUsersError('Failed to load admin user detail: $e'));
    }
  }

  Future<void> _onLoadLoginHistory(
    LoadLoginHistory event,
    Emitter<AdminUsersState> emit,
  ) async {
    emit(LoginHistoryLoading(event.adminUserId));
    try {
      final loginHistoryList =
          await _apiClient.getAdminLoginHistory(event.adminUserId);

      final loginHistory = loginHistoryList.map((login) {
        return LoginAttempt(
          id: login.id,
          adminUserId: event.adminUserId,
          timestamp: login.loginAt,
          success: login.success,
          ipAddress: login.ipAddress,
          userAgent: login.userAgent,
          failureReason: null, // Not available in current model
        );
      }).toList();

      emit(LoginHistoryLoaded(
        adminUserId: event.adminUserId,
        loginHistory: loginHistory,
      ));
    } catch (e) {
      emit(AdminUsersError('Failed to load login history: $e'));
    }
  }
}
