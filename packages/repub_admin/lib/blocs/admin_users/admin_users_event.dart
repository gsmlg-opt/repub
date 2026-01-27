import 'package:equatable/equatable.dart';

/// Base class for all admin users events.
abstract class AdminUsersEvent extends Equatable {
  const AdminUsersEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load admin users list.
class LoadAdminUsers extends AdminUsersEvent {
  const LoadAdminUsers();
}

/// Event to load admin user detail with login history.
class LoadAdminUserDetail extends AdminUsersEvent {
  final String adminUserId;

  const LoadAdminUserDetail(this.adminUserId);

  @override
  List<Object?> get props => [adminUserId];
}

/// Event to load login history for an admin user.
class LoadLoginHistory extends AdminUsersEvent {
  final String adminUserId;

  const LoadLoginHistory(this.adminUserId);

  @override
  List<Object?> get props => [adminUserId];
}
