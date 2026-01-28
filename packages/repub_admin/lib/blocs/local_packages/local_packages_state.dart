import 'package:equatable/equatable.dart';
import '../../models/local_package_info.dart';

/// Base class for all local packages states.
abstract class LocalPackagesState extends Equatable {
  const LocalPackagesState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class LocalPackagesInitial extends LocalPackagesState {
  const LocalPackagesInitial();
}

/// State when packages are being loaded.
class LocalPackagesLoading extends LocalPackagesState {
  const LocalPackagesLoading();
}

/// State when packages are successfully loaded.
class LocalPackagesLoaded extends LocalPackagesState {
  final List<LocalPackageInfo> packages;
  final int total;
  final int page;
  final int limit;
  final String? searchQuery;

  const LocalPackagesLoaded({
    required this.packages,
    required this.total,
    required this.page,
    required this.limit,
    this.searchQuery,
  });

  int get totalPages => (total / limit).ceil();
  bool get hasPrevPage => page > 1;
  bool get hasNextPage => page < totalPages;

  LocalPackagesLoaded copyWith({
    List<LocalPackageInfo>? packages,
    int? total,
    int? page,
    int? limit,
    String? searchQuery,
  }) {
    return LocalPackagesLoaded(
      packages: packages ?? this.packages,
      total: total ?? this.total,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [packages, total, page, limit, searchQuery];
}

/// State when packages loading fails.
class LocalPackagesError extends LocalPackagesState {
  final String message;

  const LocalPackagesError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when a package is being deleted.
class LocalPackageDeleting extends LocalPackagesState {
  final String packageName;

  const LocalPackageDeleting(this.packageName);

  @override
  List<Object?> get props => [packageName];
}

/// State when a package is successfully deleted.
class LocalPackageDeleted extends LocalPackagesState {
  final String packageName;
  final String message;

  const LocalPackageDeleted(this.packageName, this.message);

  @override
  List<Object?> get props => [packageName, message];
}

/// State when package deletion fails.
class LocalPackageDeleteError extends LocalPackagesState {
  final String message;

  const LocalPackageDeleteError(this.message);

  @override
  List<Object?> get props => [message];
}
