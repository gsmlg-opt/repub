import 'package:equatable/equatable.dart';
import '../../models/admin_user_info.dart';

/// Base class for all admin users states.
abstract class AdminUsersState extends Equatable {
  const AdminUsersState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class AdminUsersInitial extends AdminUsersState {
  const AdminUsersInitial();
}

/// State when admin users are being loaded.
class AdminUsersLoading extends AdminUsersState {
  const AdminUsersLoading();
}

/// State when admin users list is successfully loaded.
class AdminUsersLoaded extends AdminUsersState {
  final List<AdminUserInfo> adminUsers;

  const AdminUsersLoaded(this.adminUsers);

  @override
  List<Object?> get props => [adminUsers];
}

/// State when admin users loading fails.
class AdminUsersError extends AdminUsersState {
  final String message;

  const AdminUsersError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when admin user detail is being loaded.
class AdminUserDetailLoading extends AdminUsersState {
  final String adminUserId;

  const AdminUserDetailLoading(this.adminUserId);

  @override
  List<Object?> get props => [adminUserId];
}

/// State when admin user detail is successfully loaded.
class AdminUserDetailLoaded extends AdminUsersState {
  final AdminUserInfo adminUser;
  final List<LoginAttempt> loginHistory;

  const AdminUserDetailLoaded({
    required this.adminUser,
    required this.loginHistory,
  });

  int get totalLogins => loginHistory.where((a) => a.success).length;
  int get failedLogins => loginHistory.where((a) => !a.success).length;
  int get suspiciousAttempts =>
      loginHistory.where((a) => a.isSuspicious).length;

  @override
  List<Object?> get props => [adminUser, loginHistory];
}

/// State when login history is being loaded.
class LoginHistoryLoading extends AdminUsersState {
  final String adminUserId;

  const LoginHistoryLoading(this.adminUserId);

  @override
  List<Object?> get props => [adminUserId];
}

/// State when login history is successfully loaded.
class LoginHistoryLoaded extends AdminUsersState {
  final String adminUserId;
  final List<LoginAttempt> loginHistory;

  const LoginHistoryLoaded({
    required this.adminUserId,
    required this.loginHistory,
  });

  @override
  List<Object?> get props => [adminUserId, loginHistory];
}
