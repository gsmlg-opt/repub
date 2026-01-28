import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:repub_model/repub_model.dart' as repub_model;
import '../../services/admin_api_client.dart';
import '../../models/cached_package_info.dart';
import 'cached_packages_event.dart';
import 'cached_packages_state.dart';

/// BLoC that manages cached packages state and handles cache events.
class CachedPackagesBloc
    extends Bloc<CachedPackagesEvent, CachedPackagesState> {
  final AdminApiClient _apiClient;

  CachedPackagesBloc({AdminApiClient? apiClient})
      : _apiClient = apiClient ?? AdminApiClient(),
        super(const CachedPackagesInitial()) {
    on<CachedPackagesLoadRequested>(_onLoadRequested);
    on<CachedPackagesSearchChanged>(_onSearchChanged);
    on<CachedPackageClearRequested>(_onClearRequested);
    on<CachedPackagesClearAllRequested>(_onClearAllRequested);
    on<CachedPackagesPageChanged>(_onPageChanged);
  }

  Future<void> _onLoadRequested(
    CachedPackagesLoadRequested event,
    Emitter<CachedPackagesState> emit,
  ) async {
    emit(const CachedPackagesLoading());
    try {
      final response = await _apiClient.listCachedPackages(
        page: event.page,
        limit: event.limit,
      );

      final packages = response.packages.map((pkgInfo) {
        return CachedPackageInfo(
          name: pkgInfo.package.name,
          description: _extractDescription(pkgInfo),
          latestVersion: _getLatestVersion(pkgInfo),
          createdAt: pkgInfo.package.createdAt,
          updatedAt: pkgInfo.package.updatedAt,
          versions: pkgInfo.versions.map((v) => v.version).toList(),
          source: 'pub.dev',
        );
      }).toList();

      emit(CachedPackagesLoaded(
        packages: packages,
        total: response.total,
        page: response.page,
        limit: response.limit,
        searchQuery: event.search,
      ));
    } catch (e) {
      emit(CachedPackagesError('Failed to load cached packages: $e'));
    }
  }

  Future<void> _onSearchChanged(
    CachedPackagesSearchChanged event,
    Emitter<CachedPackagesState> emit,
  ) async {
    // Reload with search query
    add(CachedPackagesLoadRequested(search: event.query));
  }

  Future<void> _onClearRequested(
    CachedPackageClearRequested event,
    Emitter<CachedPackagesState> emit,
  ) async {
    emit(CachedPackageClearing(event.packageName));
    try {
      final result = await _apiClient.clearCachedPackage(event.packageName);
      emit(CachedPackageCleared(event.packageName, result.message));

      // Reload the current view
      if (state is CachedPackagesLoaded) {
        final currentState = state as CachedPackagesLoaded;
        add(CachedPackagesLoadRequested(
          page: currentState.page,
          limit: currentState.limit,
          search: currentState.searchQuery,
        ));
      } else {
        add(const CachedPackagesLoadRequested());
      }
    } catch (e) {
      emit(CachedPackagesClearError('Failed to clear cache: $e'));
    }
  }

  Future<void> _onClearAllRequested(
    CachedPackagesClearAllRequested event,
    Emitter<CachedPackagesState> emit,
  ) async {
    emit(const CachedPackagesClearingAll());
    try {
      await _apiClient.clearCache();
      emit(const CachedPackagesClearedAll('All cache cleared successfully'));

      // Reload the cache list (should be empty now)
      add(const CachedPackagesLoadRequested());
    } catch (e) {
      emit(CachedPackagesClearError('Failed to clear all cache: $e'));
    }
  }

  Future<void> _onPageChanged(
    CachedPackagesPageChanged event,
    Emitter<CachedPackagesState> emit,
  ) async {
    if (state is CachedPackagesLoaded) {
      final currentState = state as CachedPackagesLoaded;
      add(CachedPackagesLoadRequested(
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
}
