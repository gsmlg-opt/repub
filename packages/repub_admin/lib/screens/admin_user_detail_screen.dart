import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:repub_model/repub_model.dart';

import '../services/admin_api_client.dart';
import '../widgets/admin_layout.dart';
import 'dashboard_screen.dart';

final adminUserDetailProvider =
    FutureProvider.family<AdminUserDetail, String>((ref, id) async {
  final client = ref.watch(adminApiClientProvider);
  return client.getAdminUser(id);
});

final adminLoginHistoryProvider =
    FutureProvider.family<List<AdminLoginHistory>, String>((ref, id) async {
  final client = ref.watch(adminApiClientProvider);
  return client.getAdminLoginHistory(id);
});

class AdminUserDetailScreen extends ConsumerWidget {
  final String adminUserId;

  const AdminUserDetailScreen({
    super.key,
    required this.adminUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminUserAsync = ref.watch(adminUserDetailProvider(adminUserId));

    return AdminLayout(
      currentPath: '/admin-users',
      child: adminUserAsync.when(
        data: (detail) => _buildContent(context, ref, detail),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildError(context, ref, error.toString()),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, AdminUserDetail detail) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/admin-users'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Admin User Details',
                  style: const TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.icon(
                onPressed: () {
                  ref.invalidate(adminUserDetailProvider(adminUserId));
                  ref.invalidate(adminLoginHistoryProvider(adminUserId));
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildUserInfoCard(context, detail.adminUser),
          const SizedBox(height: 24),
          _buildRecentLoginsCard(context, detail.recentLogins),
          const SizedBox(height: 24),
          _buildFullLoginHistory(context, ref),
        ],
      ),
    );
  }

  Widget _buildUserInfoCard(BuildContext context, AdminUser user) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.admin_panel_settings,
                    size: 32, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Text(
                  user.username,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Chip(
                  label: Text(
                    user.isActive ? 'Active' : 'Inactive',
                    style: const TextStyle(fontSize: 12),
                  ),
                  backgroundColor:
                      user.isActive ? Colors.green[100] : Colors.red[100],
                  labelStyle: TextStyle(
                    color: user.isActive ? Colors.green[900] : Colors.red[900],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildInfoRow(Icons.person, 'Name', user.name ?? '-'),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.fingerprint, 'ID', user.id),
            const SizedBox(height: 12),
            _buildInfoRow(
                Icons.calendar_today, 'Created', _formatDate(user.createdAt)),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.login,
              'Last Login',
              user.lastLoginAt != null
                  ? _formatDate(user.lastLoginAt!)
                  : 'Never',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentLoginsCard(
      BuildContext context, List<AdminLoginHistory> recentLogins) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Login Activity (Last 10)',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (recentLogins.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No login history available',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ),
              )
            else
              _buildLoginHistoryTable(context, recentLogins),
          ],
        ),
      ),
    );
  }

  Widget _buildFullLoginHistory(BuildContext context, WidgetRef ref) {
    final loginHistoryAsync = ref.watch(adminLoginHistoryProvider(adminUserId));

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Full Login History',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            loginHistoryAsync.when(
              data: (loginHistory) {
                if (loginHistory.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No login history available',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  );
                }
                return _buildLoginHistoryTable(context, loginHistory);
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Failed to load full login history: $error',
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginHistoryTable(
      BuildContext context, List<AdminLoginHistory> loginHistory) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Timestamp')),
          DataColumn(label: Text('IP Address')),
          DataColumn(label: Text('User Agent')),
          DataColumn(label: Text('Status')),
        ],
        rows: loginHistory
            .map((login) => _buildLoginHistoryRow(context, login))
            .toList(),
      ),
    );
  }

  DataRow _buildLoginHistoryRow(BuildContext context, AdminLoginHistory login) {
    final isSuccess = login.success;
    final rowColor = isSuccess ? null : Colors.red[50];

    return DataRow(
      color: WidgetStateProperty.all(rowColor),
      cells: [
        DataCell(
          Text(
            _formatDate(login.loginAt),
            style: TextStyle(
              color: isSuccess ? null : Colors.red[900],
            ),
          ),
        ),
        DataCell(
          Row(
            children: [
              Icon(
                Icons.location_on,
                size: 14,
                color: isSuccess ? Colors.grey[600] : Colors.red[700],
              ),
              const SizedBox(width: 4),
              Text(
                login.ipAddress ?? 'unknown',
                style: TextStyle(
                  color: isSuccess ? null : Colors.red[900],
                ),
              ),
            ],
          ),
        ),
        DataCell(
          SizedBox(
            width: 300,
            child: Text(
              login.userAgent ?? 'unknown',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isSuccess ? Colors.grey[700] : Colors.red[900],
              ),
            ),
          ),
        ),
        DataCell(
          Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.cancel,
                size: 16,
                color: isSuccess ? Colors.green[700] : Colors.red[700],
              ),
              const SizedBox(width: 4),
              Text(
                isSuccess ? 'Success' : 'Failed',
                style: TextStyle(
                  color: isSuccess ? Colors.green[900] : Colors.red[900],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }

  Widget _buildError(BuildContext context, WidgetRef ref, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load admin user details',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => context.go('/admin-users'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to List'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () {
                    ref.invalidate(adminUserDetailProvider(adminUserId));
                    ref.invalidate(adminLoginHistoryProvider(adminUserId));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
