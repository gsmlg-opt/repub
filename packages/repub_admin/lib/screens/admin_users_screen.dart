import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:repub_model/repub_model.dart';

import '../widgets/admin_layout.dart';
import 'dashboard_screen.dart';

final adminUsersProvider = FutureProvider<List<AdminUser>>((ref) async {
  final client = ref.watch(adminApiClientProvider);
  return client.listAdminUsers();
});

class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adminUsersAsync = ref.watch(adminUsersProvider);

    return AdminLayout(
      currentPath: '/admin-users',
      child: adminUsersAsync.when(
        data: (adminUsers) => _buildContent(context, ref, adminUsers),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildError(context, ref, error.toString()),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, WidgetRef ref, List<AdminUser> adminUsers) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Admin Users',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                onPressed: () => ref.invalidate(adminUsersProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${adminUsers.length} admin users',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Admin users can only be managed via CLI. Use "dart run repub_cli admin" commands to create, modify, or delete admin users.',
                    style: TextStyle(color: Colors.blue[900], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildAdminUsersTable(context, adminUsers),
        ],
      ),
    );
  }

  Widget _buildAdminUsersTable(
      BuildContext context, List<AdminUser> adminUsers) {
    return Card(
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Username')),
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Created')),
            DataColumn(label: Text('Last Login')),
            DataColumn(label: Text('Actions')),
          ],
          rows: adminUsers
              .map((user) => _buildAdminUserRow(context, user))
              .toList(),
        ),
      ),
    );
  }

  DataRow _buildAdminUserRow(BuildContext context, AdminUser user) {
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              Icon(Icons.admin_panel_settings,
                  size: 16, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                user.username,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        DataCell(Text(user.name ?? '-')),
        DataCell(
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
        ),
        DataCell(Text(_formatDate(user.createdAt))),
        DataCell(Text(
          user.lastLoginAt != null ? _formatDate(user.lastLoginAt!) : 'Never',
        )),
        DataCell(
          IconButton(
            icon: const Icon(Icons.visibility, size: 20),
            onPressed: () => context.go('/admin-users/${user.id}'),
            tooltip: 'View Details',
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
              'Failed to load admin users',
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
              onPressed: () => ref.invalidate(adminUsersProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
