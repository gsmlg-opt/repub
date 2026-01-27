import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/admin_api_client.dart';
import '../widgets/admin_layout.dart';
import '../widgets/packages_created_chart.dart';
import '../widgets/downloads_line_chart.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardData {
  final AdminStats stats;
  final Map<String, int> packagesCreated;
  final Map<String, int> downloads;

  const _DashboardData({
    required this.stats,
    required this.packagesCreated,
    required this.downloads,
  });
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _apiClient = AdminApiClient();
  late Future<_DashboardData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadData();
  }

  @override
  void dispose() {
    _apiClient.dispose();
    super.dispose();
  }

  Future<_DashboardData> _loadData() async {
    final results = await Future.wait([
      _apiClient.getStats(),
      _apiClient.getPackagesCreatedPerDay(days: 30),
      _apiClient.getDownloadsPerHour(hours: 24),
    ]);

    return _DashboardData(
      stats: results[0] as AdminStats,
      packagesCreated: results[1] as Map<String, int>,
      downloads: results[2] as Map<String, int>,
    );
  }

  void _refresh() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/',
      child: FutureBuilder<_DashboardData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _buildError(context, snapshot.error.toString());
          }

          if (!snapshot.hasData) {
            return _buildError(context, 'No data available');
          }

          return _buildDashboard(context, snapshot.data!);
        },
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, _DashboardData data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          _buildStatsGrid(context, data.stats),
          const SizedBox(height: 32),
          _buildChartsSection(context, data),
          const SizedBox(height: 32),
          _buildQuickActions(context),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, AdminStats stats) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 600
                ? 2
                : 1;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 2.5,
          children: [
            _buildStatCard(
              context,
              label: 'Total Packages',
              value: stats.totalPackages.toString(),
              color: Colors.blue,
              icon: Icons.inventory,
            ),
            _buildStatCard(
              context,
              label: 'Local Packages',
              value: stats.localPackages.toString(),
              color: Colors.green,
              icon: Icons.upload,
            ),
            _buildStatCard(
              context,
              label: 'Cached Packages',
              value: stats.cachedPackages.toString(),
              color: Colors.purple,
              icon: Icons.cached,
            ),
            _buildStatCard(
              context,
              label: 'Total Versions',
              value: stats.totalVersions.toString(),
              color: Colors.orange,
              icon: Icons.tag,
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                Icon(icon, color: color, size: 24),
              ],
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartsSection(BuildContext context, _DashboardData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Analytics',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            // Show charts side by side on wide screens, stacked on narrow screens
            if (constraints.maxWidth > 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildPackagesCreatedCard(context, data.packagesCreated),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDownloadsCard(context, data.downloads),
                  ),
                ],
              );
            } else {
              return Column(
                children: [
                  _buildPackagesCreatedCard(context, data.packagesCreated),
                  const SizedBox(height: 16),
                  _buildDownloadsCard(context, data.downloads),
                ],
              );
            }
          },
        ),
      ],
    );
  }

  Widget _buildPackagesCreatedCard(
    BuildContext context,
    Map<String, int> data,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Packages Created (Last 30 Days)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            PackagesCreatedChart(
              data: data,
              height: 300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDownloadsCard(
    BuildContext context,
    Map<String, int> data,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Downloads (Last 24 Hours)',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            DownloadsLineChart(
              data: data,
              height: 300,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildActionButton(
                  context,
                  label: 'Manage Local Packages',
                  icon: Icons.inventory,
                  color: Colors.green,
                  onTap: () => context.go('/packages/local'),
                ),
                _buildActionButton(
                  context,
                  label: 'Manage Cached Packages',
                  icon: Icons.cached,
                  color: Colors.purple,
                  onTap: () => context.go('/packages/cached'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w500,
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
              'Failed to load dashboard',
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
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
