import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:repub_model/repub_model.dart' as repub_model;
import '../../services/admin_api_client.dart';
import '../../models/package_info.dart';
import 'packages_event.dart';
import 'packages_state.dart';

/// BLoC that manages packages state and handles package events.
class PackagesBloc extends Bloc<PackagesEvent, PackagesState> {
  final AdminApiClient _apiClient;

  PackagesBloc({AdminApiClient? apiClient})
      : _apiClient = apiClient ?? AdminApiClient(),
        super(const PackagesInitial()) {
    on<LoadHostedPackages>(_onLoadHostedPackages);
    on<LoadCachedPackages>(_onLoadCachedPackages);
    on<SearchPackages>(_onSearchPackages);
    on<DeletePackage>(_onDeletePackage);
    on<DiscontinuePackage>(_onDiscontinuePackage);
    on<ClearPackageCache>(_onClearPackageCache);
    on<ClearAllCache>(_onClearAllCache);
  }

  Future<void> _onLoadHostedPackages(
    LoadHostedPackages event,
    Emitter<PackagesState> emit,
  ) async {
    emit(const PackagesLoading(PackageViewType.hosted));
    try {
      final response = await _apiClient.listHostedPackages(
        page: event.page,
        limit: event.limit,
      );

      final packages = response.packages.map((pkgInfo) {
        // Convert from existing PackageInfo to our model
        return PackageInfo(
          name: pkgInfo.package.name,
          description: _extractDescription(pkgInfo),
          latestVersion: _getLatestVersion(pkgInfo),
          createdAt: pkgInfo.package.createdAt,
          updatedAt: pkgInfo.package.updatedAt,
          downloadCount: 0, // Download count available in package detail view
          isDiscontinued: pkgInfo.package.isDiscontinued,
          versions: pkgInfo.versions.map((v) => v.version).toList(),
          uploaderEmail: _getUploaderEmail(pkgInfo),
        );
      }).toList();

      emit(PackagesLoaded(
        viewType: PackageViewType.hosted,
        packages: packages,
        total: response.total,
        page: response.page,
        limit: response.limit,
        searchQuery: event.search,
      ));
    } catch (e) {
      emit(PackagesError('Failed to load hosted packages: $e'));
    }
  }

  Future<void> _onLoadCachedPackages(
    LoadCachedPackages event,
    Emitter<PackagesState> emit,
  ) async {
    emit(const PackagesLoading(PackageViewType.cached));
    try {
      final response = await _apiClient.listCachedPackages(
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

      emit(PackagesLoaded(
        viewType: PackageViewType.cached,
        packages: packages,
        total: response.total,
        page: response.page,
        limit: response.limit,
        searchQuery: event.search,
      ));
    } catch (e) {
      emit(PackagesError('Failed to load cached packages: $e'));
    }
  }

  Future<void> _onSearchPackages(
    SearchPackages event,
    Emitter<PackagesState> emit,
  ) async {
    if (state is PackagesLoaded) {
      final currentState = state as PackagesLoaded;
      // Reload with search query
      if (currentState.viewType == PackageViewType.hosted) {
        add(LoadHostedPackages(search: event.query));
      } else {
        add(LoadCachedPackages(search: event.query));
      }
    }
  }

  Future<void> _onDeletePackage(
    DeletePackage event,
    Emitter<PackagesState> emit,
  ) async {
    emit(PackageOperationInProgress('deleting', event.packageName));
    try {
      await _apiClient.deletePackage(event.packageName);
      emit(PackageOperationSuccess(
        'Package ${event.packageName} deleted successfully',
      ));

      // Reload the current view
      if (state is PackagesLoaded) {
        final currentState = state as PackagesLoaded;
        add(LoadHostedPackages(
          page: currentState.page,
          limit: currentState.limit,
          search: currentState.searchQuery,
        ));
      } else {
        add(const LoadHostedPackages());
      }
    } catch (e) {
      emit(PackageOperationError('Failed to delete package: $e'));
    }
  }

  Future<void> _onDiscontinuePackage(
    DiscontinuePackage event,
    Emitter<PackagesState> emit,
  ) async {
    emit(PackageOperationInProgress('discontinuing', event.packageName));
    try {
      await _apiClient.discontinuePackage(event.packageName);
      emit(PackageOperationSuccess(
        'Package ${event.packageName} ${event.discontinued ? 'discontinued' : 'reactivated'}',
      ));

      // Reload the current view
      if (state is PackagesLoaded) {
        final currentState = state as PackagesLoaded;
        add(LoadHostedPackages(
          page: currentState.page,
          limit: currentState.limit,
          search: currentState.searchQuery,
        ));
      } else {
        add(const LoadHostedPackages());
      }
    } catch (e) {
      emit(PackageOperationError('Failed to update package: $e'));
    }
  }

  Future<void> _onClearPackageCache(
    ClearPackageCache event,
    Emitter<PackagesState> emit,
  ) async {
    emit(PackageOperationInProgress('clearing_cache', event.packageName));
    try {
      final result = await _apiClient.clearCachedPackage(event.packageName);
      emit(PackageOperationSuccess(result.message));

      // Reload cached packages view
      if (state is PackagesLoaded) {
        final currentState = state as PackagesLoaded;
        add(LoadCachedPackages(
          page: currentState.page,
          limit: currentState.limit,
          search: currentState.searchQuery,
        ));
      } else {
        add(const LoadCachedPackages());
      }
    } catch (e) {
      emit(PackageOperationError('Failed to clear cache: $e'));
    }
  }

  Future<void> _onClearAllCache(
    ClearAllCache event,
    Emitter<PackagesState> emit,
  ) async {
    emit(const PackageOperationInProgress('clearing_cache', 'all'));
    try {
      await _apiClient.clearCache();
      emit(const PackageOperationSuccess('All cache cleared successfully'));

      // Reload cached packages view
      add(const LoadCachedPackages());
    } catch (e) {
      emit(PackageOperationError('Failed to clear all cache: $e'));
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
