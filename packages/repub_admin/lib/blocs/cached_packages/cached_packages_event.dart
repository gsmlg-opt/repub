import 'package:equatable/equatable.dart';

/// Base class for all cached packages events.
abstract class CachedPackagesEvent extends Equatable {
  const CachedPackagesEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load cached packages.
class CachedPackagesLoadRequested extends CachedPackagesEvent {
  final int page;
  final int limit;
  final String? search;

  const CachedPackagesLoadRequested({
    this.page = 1,
    this.limit = 20,
    this.search,
  });

  @override
  List<Object?> get props => [page, limit, search];
}

/// Event to search cached packages.
class CachedPackagesSearchChanged extends CachedPackagesEvent {
  final String query;

  const CachedPackagesSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

/// Event to clear a single cached package.
class CachedPackageClearRequested extends CachedPackagesEvent {
  final String packageName;

  const CachedPackageClearRequested(this.packageName);

  @override
  List<Object?> get props => [packageName];
}

/// Event to clear all cached packages.
class CachedPackagesClearAllRequested extends CachedPackagesEvent {
  const CachedPackagesClearAllRequested();
}

/// Event to change page.
class CachedPackagesPageChanged extends CachedPackagesEvent {
  final int page;

  const CachedPackagesPageChanged(this.page);

  @override
  List<Object?> get props => [page];
}
