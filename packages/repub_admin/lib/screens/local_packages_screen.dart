import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_api_client.dart';
import '../widgets/admin_layout.dart';
import 'dashboard_screen.dart';

final localPackagesProvider =
    FutureProvider.family<PackageListResponse, int>((ref, page) async {
  final client = ref.watch(adminApiClientProvider);
  return client.listLocalPackages(page: page);
});

class LocalPackagesScreen extends ConsumerStatefulWidget {
  const LocalPackagesScreen({super.key});

  @override
  ConsumerState<LocalPackagesScreen> createState() =>
      _LocalPackagesScreenState();
}

class _LocalPackagesScreenState extends ConsumerState<LocalPackagesScreen> {
  int _currentPage = 1;

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(localPackagesProvider(_currentPage));

    return AdminLayout(
      currentPath: '/packages/local',
      child: packagesAsync.when(
        data: (response) => _buildPackageList(context, response),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildError(context, error.toString()),
      ),
    );
  }

  Widget _buildPackageList(BuildContext context, PackageListResponse response) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Local Packages',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              Text(
                '${response.total} package${response.total != 1 ? 's' : ''}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ],
          ),
        ),
        if (response.packages.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No local packages',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: response.packages.length,
              itemBuilder: (context, index) {
                final pkg = response.packages[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.inventory),
                    title: Text(
                      pkg.package.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${pkg.versions.length} version${pkg.versions.length != 1 ? 's' : ''}',
                    ),
                    trailing: pkg.package.isDiscontinued
                        ? const Chip(
                            label: Text('Discontinued'),
                            backgroundColor: Colors.orange,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        if (response.totalPages > 1) _buildPagination(response),
      ],
    );
  }

  Widget _buildPagination(PackageListResponse response) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: response.hasPrevPage
                ? () => setState(() => _currentPage--)
                : null,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Previous'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Page $_currentPage of ${response.totalPages}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          FilledButton.icon(
            onPressed: response.hasNextPage
                ? () => setState(() => _currentPage++)
                : null,
            icon: const Icon(Icons.chevron_right),
            iconAlignment: IconAlignment.end,
            label: const Text('Next'),
          ),
        ],
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () =>
                  ref.refresh(localPackagesProvider(_currentPage)),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
