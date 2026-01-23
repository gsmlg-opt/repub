import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/admin_api_client.dart';
import '../widgets/admin_layout.dart';
import 'dashboard_screen.dart';

final cachedPackagesProvider =
    FutureProvider.family<PackageListResponse, int>((ref, page) async {
  final client = ref.watch(adminApiClientProvider);
  return client.listCachedPackages(page: page);
});

class CachedPackagesScreen extends ConsumerStatefulWidget {
  const CachedPackagesScreen({super.key});

  @override
  ConsumerState<CachedPackagesScreen> createState() =>
      _CachedPackagesScreenState();
}

class _CachedPackagesScreenState extends ConsumerState<CachedPackagesScreen> {
  int _currentPage = 1;
  bool _isClearing = false;

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'Are you sure you want to clear all cached packages? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClearing = true);

    try {
      final client = ref.read(adminApiClientProvider);
      final result = await client.clearCache();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(cachedPackagesProvider(_currentPage));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to clear cache: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final packagesAsync = ref.watch(cachedPackagesProvider(_currentPage));

    return AdminLayout(
      currentPath: '/packages/cached',
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cached Packages',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${response.total} package${response.total != 1 ? 's' : ''}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: _isClearing ? null : _clearCache,
                icon: _isClearing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_sweep),
                label: const Text('Clear Cache'),
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
                  Icon(Icons.cached, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No cached packages',
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
                    leading: const Icon(Icons.cached),
                    title: Text(
                      pkg.package.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${pkg.versions.length} version${pkg.versions.length != 1 ? 's' : ''}',
                    ),
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
                  ref.refresh(cachedPackagesProvider(_currentPage)),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
