import 'package:equatable/equatable.dart';

/// Base class for all local packages events.
abstract class LocalPackagesEvent extends Equatable {
  const LocalPackagesEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load local packages.
class LocalPackagesLoadRequested extends LocalPackagesEvent {
  final int page;
  final int limit;
  final String? search;

  const LocalPackagesLoadRequested({
    this.page = 1,
    this.limit = 20,
    this.search,
  });

  @override
  List<Object?> get props => [page, limit, search];
}

/// Event to search local packages.
class LocalPackagesSearchChanged extends LocalPackagesEvent {
  final String query;

  const LocalPackagesSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

/// Event to delete a local package.
class LocalPackageDeleteRequested extends LocalPackagesEvent {
  final String packageName;

  const LocalPackageDeleteRequested(this.packageName);

  @override
  List<Object?> get props => [packageName];
}

/// Event to discontinue a local package.
class LocalPackageDiscontinueRequested extends LocalPackagesEvent {
  final String packageName;
  final bool discontinued;

  const LocalPackageDiscontinueRequested(
    this.packageName, {
    this.discontinued = true,
  });

  @override
  List<Object?> get props => [packageName, discontinued];
}

/// Event to change page.
class LocalPackagesPageChanged extends LocalPackagesEvent {
  final int page;

  const LocalPackagesPageChanged(this.page);

  @override
  List<Object?> get props => [page];
}
