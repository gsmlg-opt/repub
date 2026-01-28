import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:repub_model/repub_model.dart' as repub_model;
import '../../services/admin_api_client.dart';
import '../../models/package_info.dart';
import 'local_packages_event.dart';
import 'local_packages_state.dart';

/// BLoC that manages local (hosted) packages state and handles package events.
class LocalPackagesBloc
    extends Bloc<LocalPackagesEvent, LocalPackagesState> {
  final AdminApiClient _apiClient;

  LocalPackagesBloc({AdminApiClient? apiClient})
      : _apiClient = apiClient ?? AdminApiClient(),
        super(const LocalPackagesInitial()) {
    on<LocalPackagesLoadRequested>(_onLoadRequested);
    on<LocalPackagesSearchChanged>(_onSearchChanged);
    on<LocalPackageDeleteRequested>(_onDeleteRequested);
    on<LocalPackageDiscontinueRequested>(_onDiscontinueRequested);
    on<LocalPackagesPageChanged>(_onPageChanged);
  }

  Future<void> _onLoadRequested(
    LocalPackagesLoadRequested event,
    Emitter<LocalPackagesState> emit,
  ) async {
    emit(const LocalPackagesLoading());
    try {
      final response = await _apiClient.listHostedPackages(
        page: event.page,
        limit: event.limit,
      );

      final packages = response.packages.map((pkgInfo) {
        return PackageInfo(
          name: pkgInfo.package.name,
          description: _extractDescription(pkgInfo),
          latestVersion: _getLatestVersion(pkgInfo),
          createdAt: pkgInfo.package.createdAt,
          updatedAt: pkgInfo.package.updatedAt,
          downloadCount: 0,
          isDiscontinued: pkgInfo.package.isDiscontinued,
          versions: pkgInfo.versions.map((v) => v.version).toList(),
          uploaderEmail: _getUploaderEmail(pkgInfo),
        );
      }).toList();

      emit(LocalPackagesLoaded(
        packages: packages,
        total: response.total,
        page: response.page,
        limit: response.limit,
        searchQuery: event.search,
      ));
    } catch (e) {
      emit(LocalPackagesError('Failed to load local packages: $e'));
    }
  }

  Future<void> _onSearchChanged(
    LocalPackagesSearchChanged event,
    Emitter<LocalPackagesState> emit,
  ) async {
    // Reload with search query
    add(LocalPackagesLoadRequested(search: event.query));
  }

  Future<void> _onDeleteRequested(
    LocalPackageDeleteRequested event,
    Emitter<LocalPackagesState> emit,
  ) async {
    emit(LocalPackageDeleting(event.packageName));
    try {
      await _apiClient.deletePackage(event.packageName);
      emit(LocalPackageDeleted(
        event.packageName,
        'Package ${event.packageName} deleted successfully',
      ));

      // Reload the current view
      if (state is LocalPackagesLoaded) {
        final currentState = state as LocalPackagesLoaded;
        add(LocalPackagesLoadRequested(
          page: currentState.page,
          limit: currentState.limit,
          search: currentState.searchQuery,
        ));
      } else {
        add(const LocalPackagesLoadRequested());
      }
    } catch (e) {
      emit(LocalPackageDeleteError('Failed to delete package: $e'));
    }
  }

  Future<void> _onDiscontinueRequested(
    LocalPackageDiscontinueRequested event,
    Emitter<LocalPackagesState> emit,
  ) async {
    emit(LocalPackageDeleting(event.packageName));
    try {
      await _apiClient.discontinuePackage(event.packageName);
      emit(LocalPackageDeleted(
        event.packageName,
        'Package ${event.packageName} ${event.discontinued ? "discontinued" : "reactivated"}',
      ));

      // Reload the current view
      if (state is LocalPackagesLoaded) {
        final currentState = state as LocalPackagesLoaded;
        add(LocalPackagesLoadRequested(
          page: currentState.page,
          limit: currentState.limit,
          search: currentState.searchQuery,
        ));
      } else {
        add(const LocalPackagesLoadRequested());
      }
    } catch (e) {
      emit(LocalPackageDeleteError('Failed to update package: $e'));
    }
  }

  Future<void> _onPageChanged(
    LocalPackagesPageChanged event,
    Emitter<LocalPackagesState> emit,
  ) async {
    if (state is LocalPackagesLoaded) {
      final currentState = state as LocalPackagesLoaded;
      add(LocalPackagesLoadRequested(
        page: event.page,
        limit: currentState.limit,
        search: currentState.searchQuery,
      ));
    }
  }

  // Helper methods to extract data from existing PackageInfo model

  String _extractDescription(repub_model.PackageInfo pkgInfo) {
    if (pkgInfo.versions.isEmpty) return '';
    final latestVersion = pkgInfo.versions.first;
    final pubspec = latestVersion.pubspec;
    return pubspec['description'] as String? ?? '';
  }

  String _getLatestVersion(repub_model.PackageInfo pkgInfo) {
    if (pkgInfo.versions.isEmpty) return '0.0.0';
    return pkgInfo.versions.first.version;
  }

  String? _getUploaderEmail(repub_model.PackageInfo pkgInfo) {
    if (pkgInfo.versions.isEmpty) return null;
    final latestVersion = pkgInfo.versions.first;
    final pubspec = latestVersion.pubspec;
    final author = pubspec['author'] as String?;
    return author;
  }
}
