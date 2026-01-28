import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/cached_packages/cached_packages_bloc.dart';
import '../blocs/cached_packages/cached_packages_event.dart';
import '../blocs/cached_packages/cached_packages_state.dart';
import '../models/package_info.dart';
import '../widgets/admin_layout.dart';

class CachedPackagesScreen extends StatefulWidget {
  const CachedPackagesScreen({super.key});

  @override
  State<CachedPackagesScreen> createState() => _CachedPackagesScreenState();
}

class _CachedPackagesScreenState extends State<CachedPackagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Load cached packages when screen initializes
    context.read<CachedPackagesBloc>().add(const CachedPackagesLoadRequested());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      context.read<CachedPackagesBloc>().add(CachedPackagesSearchChanged(query));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/packages/cached',
      child: BlocConsumer<CachedPackagesBloc, CachedPackagesState>(
        listener: (context, state) {
          if (state is CachedPackageCleared) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is CachedPackagesClearError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, state),
              Expanded(child: _buildContent(context, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CachedPackagesState state) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Cached Packages',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  if (state is CachedPackagesLoaded)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Chip(
                        label: Text('${state.total} cached'),
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () => _showCachedPackagesClearAllRequestedDialog(context),
                    icon: const Icon(Icons.delete_sweep),
                    label: const Text('Clear All Cache'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      context
                          .read<CachedPackagesBloc>()
                          .add(const CachedPackagesLoadRequested());
                    },
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Packages cached from upstream registry (pub.dev)',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 400,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search cached packages...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, CachedPackagesState state) {
    if (state is CachedPackagesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is CachedPackagesError) {
      return _buildError(context, state.message);
    }

    if (state is CachedPackagesLoaded) {
      if (state.packages.isEmpty) {
        return _buildEmptyState(context, state.searchQuery);
      }
      return _buildPackagesTable(context, state);
    }

    if (state is CachedPackageClearing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Clearing cache for ${state.packageName}...'),
          ],
        ),
      );
    }

    // Initial state - reload
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildPackagesTable(BuildContext context, CachedPackagesLoaded state) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 2,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Package Name')),
                  DataColumn(label: Text('Version')),
                  DataColumn(label: Text('Cached Versions'), numeric: true),
                  DataColumn(label: Text('Source')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: state.packages.map((pkg) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          pkg.name,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            pkg.latestVersion,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.secondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text('${pkg.versions.length}')),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.cloud_download,
                              size: 16,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'pub.dev',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(_buildActionButtons(context, pkg)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        _buildPaginationControls(context, state),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, PackageInfo pkg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.open_in_new, size: 20),
          onPressed: () {
            // Open on pub.dev in new tab
            // Note: In a real app, use url_launcher package
          },
          tooltip: 'View on pub.dev',
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          onPressed: () => _showClearCacheDialog(context, pkg),
          tooltip: 'Clear from cache',
          color: Colors.orange,
        ),
      ],
    );
  }

  Widget _buildPaginationControls(BuildContext context, CachedPackagesLoaded state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: state.hasPrevPage
                ? () {
                    context.read<CachedPackagesBloc>().add(
                          CachedPackagesLoadRequested(
                            page: state.page - 1,
                            limit: state.limit,
                            search: state.searchQuery,
                          ),
                        );
                  }
                : null,
            tooltip: 'Previous page',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Page ${state.page} of ${state.totalPages}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: state.hasNextPage
                ? () {
                    context.read<CachedPackagesBloc>().add(
                          CachedPackagesLoadRequested(
                            page: state.page + 1,
                            limit: state.limit,
                            search: state.searchQuery,
                          ),
                        );
                  }
                : null,
            tooltip: 'Next page',
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, String? searchQuery) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              searchQuery != null && searchQuery.isNotEmpty
                  ? Icons.search_off
                  : Icons.cached,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery != null && searchQuery.isNotEmpty
                  ? 'No cached packages found matching "$searchQuery"'
                  : 'No cached packages',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              searchQuery != null && searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Packages downloaded from pub.dev will be cached here',
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            if (searchQuery != null && searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextButton.icon(
                  icon: const Icon(Icons.clear),
                  label: const Text('Clear search'),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load cached packages',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                context.read<CachedPackagesBloc>().add(const CachedPackagesLoadRequested());
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context, PackageInfo pkg) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.orange[700]),
            const SizedBox(width: 8),
            const Text('Clear Cache'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remove "${pkg.name}" from the cache?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'This will remove ${pkg.versions.length} cached version(s). '
              'The package will be re-downloaded from pub.dev when needed.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<CachedPackagesBloc>().add(CachedPackageClearRequested(pkg.name));
            },
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );
  }

  void _showCachedPackagesClearAllRequestedDialog(BuildContext context) {
    final TextEditingController confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red[700]),
            const SizedBox(width: 8),
            const Text('Clear All Cache'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to clear all cached packages?',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'This will remove all packages cached from pub.dev. '
              'They will be re-downloaded when needed.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              decoration: const InputDecoration(
                labelText: 'Type "CLEAR ALL CACHE" to confirm',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              if (confirmController.text == 'CLEAR ALL CACHE') {
                Navigator.of(dialogContext).pop();
                context.read<CachedPackagesBloc>().add(const CachedPackagesClearAllRequested());
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Confirmation text does not match'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
