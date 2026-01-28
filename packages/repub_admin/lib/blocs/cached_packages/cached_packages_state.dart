import 'package:equatable/equatable.dart';
import '../../models/package_info.dart';

/// Base class for all cached packages states.
abstract class CachedPackagesState extends Equatable {
  const CachedPackagesState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class CachedPackagesInitial extends CachedPackagesState {
  const CachedPackagesInitial();
}

/// State when packages are being loaded.
class CachedPackagesLoading extends CachedPackagesState {
  const CachedPackagesLoading();
}

/// State when packages are successfully loaded.
class CachedPackagesLoaded extends CachedPackagesState {
  final List<PackageInfo> packages;
  final int total;
  final int page;
  final int limit;
  final String? searchQuery;
  final int totalStorageBytes;

  const CachedPackagesLoaded({
    required this.packages,
    required this.total,
    required this.page,
    required this.limit,
    this.searchQuery,
    this.totalStorageBytes = 0,
  });

  int get totalPages => (total / limit).ceil();
  bool get hasPrevPage => page > 1;
  bool get hasNextPage => page < totalPages;

  CachedPackagesLoaded copyWith({
    List<PackageInfo>? packages,
    int? total,
    int? page,
    int? limit,
    String? searchQuery,
    int? totalStorageBytes,
  }) {
    return CachedPackagesLoaded(
      packages: packages ?? this.packages,
      total: total ?? this.total,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      searchQuery: searchQuery ?? this.searchQuery,
      totalStorageBytes: totalStorageBytes ?? this.totalStorageBytes,
    );
  }

  @override
  List<Object?> get props =>
      [packages, total, page, limit, searchQuery, totalStorageBytes];
}

/// State when packages loading fails.
class CachedPackagesError extends CachedPackagesState {
  final String message;

  const CachedPackagesError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when clearing a cached package.
class CachedPackageClearing extends CachedPackagesState {
  final String packageName;

  const CachedPackageClearing(this.packageName);

  @override
  List<Object?> get props => [packageName];
}

/// State when a cached package is successfully cleared.
class CachedPackageCleared extends CachedPackagesState {
  final String packageName;
  final String message;

  const CachedPackageCleared(this.packageName, this.message);

  @override
  List<Object?> get props => [packageName, message];
}

/// State when clearing all cached packages.
class CachedPackagesClearingAll extends CachedPackagesState {
  const CachedPackagesClearingAll();
}

/// State when all cached packages are successfully cleared.
class CachedPackagesClearedAll extends CachedPackagesState {
  final String message;

  const CachedPackagesClearedAll(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when cache clearing fails.
class CachedPackagesClearError extends CachedPackagesState {
  final String message;

  const CachedPackagesClearError(this.message);

  @override
  List<Object?> get props => [message];
}
