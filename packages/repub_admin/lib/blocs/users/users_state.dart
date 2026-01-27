import 'package:equatable/equatable.dart';
import '../../models/user_info.dart';

/// Base class for all users states.
abstract class UsersState extends Equatable {
  const UsersState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class UsersInitial extends UsersState {
  const UsersInitial();
}

/// State when users are being loaded.
class UsersLoading extends UsersState {
  const UsersLoading();
}

/// State when users are successfully loaded.
class UsersLoaded extends UsersState {
  final List<UserInfo> users;
  final int total;
  final int page;
  final int limit;
  final String? searchQuery;
  final bool? activeOnly;

  const UsersLoaded({
    required this.users,
    required this.total,
    required this.page,
    required this.limit,
    this.searchQuery,
    this.activeOnly,
  });

  int get totalPages => (total / limit).ceil();
  bool get hasPrevPage => page > 1;
  bool get hasNextPage => page < totalPages;

  UsersLoaded copyWith({
    List<UserInfo>? users,
    int? total,
    int? page,
    int? limit,
    String? searchQuery,
    bool? activeOnly,
  }) {
    return UsersLoaded(
      users: users ?? this.users,
      total: total ?? this.total,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      searchQuery: searchQuery ?? this.searchQuery,
      activeOnly: activeOnly ?? this.activeOnly,
    );
  }

  @override
  List<Object?> get props => [
        users,
        total,
        page,
        limit,
        searchQuery,
        activeOnly,
      ];
}

/// State when users loading fails.
class UsersError extends UsersState {
  final String message;

  const UsersError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when a user operation is in progress.
class UserOperationInProgress extends UsersState {
  final String operation; // 'activating', 'deactivating', 'deleting'
  final String userId;

  const UserOperationInProgress(this.operation, this.userId);

  @override
  List<Object?> get props => [operation, userId];
}

/// State when a user operation succeeds.
class UserOperationSuccess extends UsersState {
  final String message;

  const UserOperationSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when a user operation fails.
class UserOperationError extends UsersState {
  final String message;

  const UserOperationError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when user tokens are loaded.
class UserTokensLoaded extends UsersState {
  final String userId;
  final List<TokenInfo> tokens;

  const UserTokensLoaded({
    required this.userId,
    required this.tokens,
  });

  @override
  List<Object?> get props => [userId, tokens];
}
