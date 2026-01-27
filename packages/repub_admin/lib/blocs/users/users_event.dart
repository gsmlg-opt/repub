import 'package:equatable/equatable.dart';

/// Base class for all users events.
abstract class UsersEvent extends Equatable {
  const UsersEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load users list.
class LoadUsers extends UsersEvent {
  final int page;
  final int limit;
  final String? search;
  final bool? activeOnly;

  const LoadUsers({
    this.page = 1,
    this.limit = 20,
    this.search,
    this.activeOnly,
  });

  @override
  List<Object?> get props => [page, limit, search, activeOnly];
}

/// Event to search users.
class SearchUsers extends UsersEvent {
  final String query;

  const SearchUsers(this.query);

  @override
  List<Object?> get props => [query];
}

/// Event to activate a user.
class ActivateUser extends UsersEvent {
  final String userId;

  const ActivateUser(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Event to deactivate a user.
class DeactivateUser extends UsersEvent {
  final String userId;

  const DeactivateUser(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Event to delete a user.
class DeleteUser extends UsersEvent {
  final String userId;

  const DeleteUser(this.userId);

  @override
  List<Object?> get props => [userId];
}

/// Event to view user tokens.
class ViewUserTokens extends UsersEvent {
  final String userId;

  const ViewUserTokens(this.userId);

  @override
  List<Object?> get props => [userId];
}
