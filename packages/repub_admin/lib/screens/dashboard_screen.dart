import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../blocs/dashboard/dashboard_bloc.dart';
import '../blocs/dashboard/dashboard_event.dart';
import '../blocs/dashboard/dashboard_state.dart';
import '../models/dashboard_stats.dart';
import '../widgets/admin_layout.dart';

/// Dashboard screen that displays statistics and analytics using BLoC pattern.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Load dashboard data when screen is built
    context.read<DashboardBloc>().add(const LoadDashboard());

    return AdminLayout(
      currentPath: '/',
      child: BlocBuilder<DashboardBloc, DashboardState>(
        builder: (context, state) {
          if (state is DashboardLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is DashboardError) {
            return _buildError(context, state.message);
          }

          if (state is DashboardLoaded) {
            return _buildDashboard(context, state.stats);
          }

          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, DashboardStats stats) {
    return RefreshIndicator(
      onRefresh: () async {
        context.read<DashboardBloc>().add(const RefreshDashboard());
        // Wait for the refresh to complete
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dashboard',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    context.read<DashboardBloc>().add(const RefreshDashboard());
                  },
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildStatsGrid(context, stats),
            const SizedBox(height: 32),
            if (stats.recentActivity.isNotEmpty) ...[
              _buildRecentActivity(context, stats.recentActivity),
              const SizedBox(height: 32),
            ],
            _buildQuickActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context, DashboardStats stats) {
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
              label: 'Total Users',
              value: stats.totalUsers.toString(),
              color: Colors.green,
              icon: Icons.people,
            ),
            _buildStatCard(
              context,
              label: 'Total Downloads',
              value: stats.totalDownloads.toString(),
              color: Colors.purple,
              icon: Icons.download,
            ),
            _buildStatCard(
              context,
              label: 'Active Tokens',
              value: stats.activeTokens.toString(),
              color: Colors.orange,
              icon: Icons.key,
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
                Flexible(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                    overflow: TextOverflow.ellipsis,
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

  Widget _buildRecentActivity(
    BuildContext context,
    List<RecentActivity> activities,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Activity',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: activities.length > 10 ? 10 : activities.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final activity = activities[index];
                return ListTile(
                  leading: _getActivityIcon(activity.type),
                  title: Text(activity.description),
                  subtitle: Text(_formatTimestamp(activity.timestamp)),
                  dense: true,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Icon _getActivityIcon(String type) {
    IconData iconData;
    Color color;

    switch (type) {
      case 'package_published':
        iconData = Icons.upload;
        color = Colors.green;
        break;
      case 'user_registered':
        iconData = Icons.person_add;
        color = Colors.blue;
        break;
      case 'download':
        iconData = Icons.download;
        color = Colors.purple;
        break;
      case 'admin_login':
        iconData = Icons.login;
        color = Colors.teal;
        break;
      case 'package_deleted':
        iconData = Icons.delete_forever;
        color = Colors.red;
        break;
      case 'package_version_deleted':
        iconData = Icons.delete_outline;
        color = Colors.orange;
        break;
      case 'user_created':
        iconData = Icons.person_add_alt_1;
        color = Colors.indigo;
        break;
      case 'user_deleted':
        iconData = Icons.person_remove;
        color = Colors.red;
        break;
      case 'config_updated':
        iconData = Icons.settings;
        color = Colors.amber;
        break;
      case 'cache_cleared':
        iconData = Icons.cleaning_services;
        color = Colors.brown;
        break;
      default:
        iconData = Icons.circle;
        color = Colors.grey;
    }

    return Icon(iconData, color: color, size: 20);
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.month}/${timestamp.day}/${timestamp.year}';
    }
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
                _buildActionButton(
                  context,
                  label: 'Manage Users',
                  icon: Icons.people,
                  color: Colors.blue,
                  onTap: () => context.go('/users'),
                ),
                _buildActionButton(
                  context,
                  label: 'Site Configuration',
                  icon: Icons.settings,
                  color: Colors.orange,
                  onTap: () => context.go('/config'),
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
              onPressed: () {
                context.read<DashboardBloc>().add(const LoadDashboard());
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
