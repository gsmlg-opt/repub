import 'package:equatable/equatable.dart';

/// Base class for all packages events.
abstract class PackagesEvent extends Equatable {
  const PackagesEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load hosted packages (packages published directly to this registry).
class LoadHostedPackages extends PackagesEvent {
  final int page;
  final int limit;
  final String? search;

  const LoadHostedPackages({
    this.page = 1,
    this.limit = 20,
    this.search,
  });

  @override
  List<Object?> get props => [page, limit, search];
}

/// Event to load cached packages (packages cached from upstream registry).
class LoadCachedPackages extends PackagesEvent {
  final int page;
  final int limit;
  final String? search;

  const LoadCachedPackages({
    this.page = 1,
    this.limit = 20,
    this.search,
  });

  @override
  List<Object?> get props => [page, limit, search];
}

/// Event to search packages (applies to current view).
class SearchPackages extends PackagesEvent {
  final String query;

  const SearchPackages(this.query);

  @override
  List<Object?> get props => [query];
}

/// Event to delete a hosted package.
class DeletePackage extends PackagesEvent {
  final String packageName;

  const DeletePackage(this.packageName);

  @override
  List<Object?> get props => [packageName];
}

/// Event to discontinue a package.
class DiscontinuePackage extends PackagesEvent {
  final String packageName;
  final bool discontinued;

  const DiscontinuePackage(this.packageName, this.discontinued);

  @override
  List<Object?> get props => [packageName, discontinued];
}

/// Event to clear cached package.
class ClearPackageCache extends PackagesEvent {
  final String packageName;

  const ClearPackageCache(this.packageName);

  @override
  List<Object?> get props => [packageName];
}

/// Event to clear all cached packages.
class ClearAllCache extends PackagesEvent {
  const ClearAllCache();
}
