import 'package:equatable/equatable.dart';
import '../../models/package_info.dart';

/// Type of package view.
/// - hosted: Packages published directly to this registry
/// - cached: Packages cached from upstream registry (pub.dev)
enum PackageViewType { hosted, cached }

/// Base class for all packages states.
abstract class PackagesState extends Equatable {
  const PackagesState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class PackagesInitial extends PackagesState {
  const PackagesInitial();
}

/// State when packages are being loaded.
class PackagesLoading extends PackagesState {
  final PackageViewType viewType;

  const PackagesLoading(this.viewType);

  @override
  List<Object?> get props => [viewType];
}

/// State when packages are successfully loaded.
class PackagesLoaded extends PackagesState {
  final PackageViewType viewType;
  final List<PackageInfo> packages;
  final int total;
  final int page;
  final int limit;
  final String? searchQuery;

  const PackagesLoaded({
    required this.viewType,
    required this.packages,
    required this.total,
    required this.page,
    required this.limit,
    this.searchQuery,
  });

  int get totalPages => (total / limit).ceil();
  bool get hasPrevPage => page > 1;
  bool get hasNextPage => page < totalPages;

  PackagesLoaded copyWith({
    PackageViewType? viewType,
    List<PackageInfo>? packages,
    int? total,
    int? page,
    int? limit,
    String? searchQuery,
  }) {
    return PackagesLoaded(
      viewType: viewType ?? this.viewType,
      packages: packages ?? this.packages,
      total: total ?? this.total,
      page: page ?? this.page,
      limit: limit ?? this.limit,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  @override
  List<Object?> get props => [
        viewType,
        packages,
        total,
        page,
        limit,
        searchQuery,
      ];
}

/// State when packages loading fails.
class PackagesError extends PackagesState {
  final String message;

  const PackagesError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when a package operation is in progress.
class PackageOperationInProgress extends PackagesState {
  final String operation; // 'deleting', 'discontinuing', 'clearing_cache'
  final String packageName;

  const PackageOperationInProgress(this.operation, this.packageName);

  @override
  List<Object?> get props => [operation, packageName];
}

/// State when a package operation succeeds.
class PackageOperationSuccess extends PackagesState {
  final String message;

  const PackageOperationSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when a package operation fails.
class PackageOperationError extends PackagesState {
  final String message;

  const PackageOperationError(this.message);

  @override
  List<Object?> get props => [message];
}
