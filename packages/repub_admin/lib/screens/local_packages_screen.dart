import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../blocs/local_packages/local_packages_bloc.dart';
import '../blocs/local_packages/local_packages_event.dart';
import '../blocs/local_packages/local_packages_state.dart';
import '../models/local_package_info.dart';
import '../widgets/admin_layout.dart';

class LocalPackagesScreen extends StatefulWidget {
  const LocalPackagesScreen({super.key});

  @override
  State<LocalPackagesScreen> createState() => _LocalPackagesScreenState();
}

class _LocalPackagesScreenState extends State<LocalPackagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    // Load packages when screen initializes
    context.read<LocalPackagesBloc>().add(const LocalPackagesLoadRequested());
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
      context.read<LocalPackagesBloc>().add(LocalPackagesSearchChanged(query));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/packages/local',
      child: BlocConsumer<LocalPackagesBloc, LocalPackagesState>(
        listener: (context, state) {
          if (state is LocalPackageDeleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is LocalPackageDeleteError) {
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

  Widget _buildHeader(BuildContext context, LocalPackagesState state) {
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
                'Hosted Packages',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  if (state is LocalPackagesLoaded)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Chip(
                        label: Text('${state.total} packages'),
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      context
                          .read<LocalPackagesBloc>()
                          .add(const LocalPackagesLoadRequested());
                    },
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: 400,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search packages...',
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

  Widget _buildContent(BuildContext context, LocalPackagesState state) {
    if (state is LocalPackagesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is LocalPackagesError) {
      return _buildError(context, state.message);
    }

    if (state is LocalPackagesLoaded) {
      if (state.packages.isEmpty) {
        return _buildEmptyState(context, state.searchQuery);
      }
      return _buildPackagesTable(context, state);
    }

    if (state is LocalPackageDeleting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Deleting ${state.packageName}...'),
          ],
        ),
      );
    }

    // Initial state or after operation - reload
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildPackagesTable(BuildContext context, LocalPackagesLoaded state) {
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
                  DataColumn(label: Text('Versions'), numeric: true),
                  DataColumn(label: Text('Downloads'), numeric: true),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: state.packages.map((pkg) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () =>
                                  context.go('/packages/${pkg.name}/stats'),
                              child: Text(
                                pkg.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(context).colorScheme.primary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                            if (pkg.isDiscontinued)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Tooltip(
                                  message: 'This package is discontinued',
                                  child: Icon(
                                    Icons.warning_amber,
                                    size: 16,
                                    color: Colors.orange[700],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            pkg.latestVersion,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      DataCell(Text('${pkg.versions.length}')),
                      DataCell(Text('${pkg.downloadCount}')),
                      DataCell(_buildStatusBadge(context, pkg)),
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

  Widget _buildStatusBadge(BuildContext context, LocalPackageInfo pkg) {
    if (pkg.isDiscontinued) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Discontinued',
          style: TextStyle(
            color: Colors.orange[900],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Active',
        style: TextStyle(
          color: Colors.green[900],
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, LocalPackageInfo pkg) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            pkg.isDiscontinued ? Icons.play_arrow : Icons.pause,
            size: 20,
          ),
          onPressed: () => _showDiscontinueDialog(context, pkg),
          tooltip: pkg.isDiscontinued ? 'Reactivate' : 'Discontinue',
        ),
        IconButton(
          icon: const Icon(Icons.delete, size: 20),
          onPressed: () => _showDeleteDialog(context, pkg),
          tooltip: 'Delete package',
          color: Colors.red,
        ),
      ],
    );
  }

  Widget _buildPaginationControls(
      BuildContext context, LocalPackagesLoaded state) {
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
                    context.read<LocalPackagesBloc>().add(
                          LocalPackagesLoadRequested(
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
                    context.read<LocalPackagesBloc>().add(
                          LocalPackagesLoadRequested(
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
                  : Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery != null && searchQuery.isNotEmpty
                  ? 'No packages found matching "$searchQuery"'
                  : 'No hosted packages yet',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              searchQuery != null && searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Packages published to this registry will appear here',
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
              'Failed to load packages',
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
                context
                    .read<LocalPackagesBloc>()
                    .add(const LocalPackagesLoadRequested());
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, LocalPackageInfo pkg) {
    final TextEditingController confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red[700]),
            const SizedBox(width: 8),
            const Text('Delete Package'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${pkg.name}"?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'This will delete all ${pkg.versions.length} version(s) and cannot be undone.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              decoration: InputDecoration(
                labelText: 'Type "${pkg.name}" to confirm',
                border: const OutlineInputBorder(),
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
              if (confirmController.text == pkg.name) {
                Navigator.of(dialogContext).pop();
                context
                    .read<LocalPackagesBloc>()
                    .add(LocalPackageDeleteRequested(pkg.name));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Package name does not match'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDiscontinueDialog(BuildContext context, LocalPackageInfo pkg) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              pkg.isDiscontinued ? Icons.play_arrow : Icons.pause,
              color: Colors.orange[700],
            ),
            const SizedBox(width: 8),
            Text(pkg.isDiscontinued
                ? 'Reactivate Package'
                : 'Discontinue Package'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              pkg.isDiscontinued
                  ? 'Are you sure you want to reactivate "${pkg.name}"?'
                  : 'Are you sure you want to discontinue "${pkg.name}"?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              pkg.isDiscontinued
                  ? 'This package will become available for new installations.'
                  : 'Discontinued packages can still be used by existing projects but are marked as not recommended for new use.',
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
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.read<LocalPackagesBloc>().add(
                    LocalPackageDiscontinueRequested(
                      pkg.name,
                      discontinued: !pkg.isDiscontinued,
                    ),
                  );
            },
            child: Text(pkg.isDiscontinued ? 'Reactivate' : 'Discontinue'),
          ),
        ],
      ),
    );
  }
}
