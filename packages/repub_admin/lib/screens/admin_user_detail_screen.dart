import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../blocs/admin_users/admin_users_bloc.dart';
import '../blocs/admin_users/admin_users_event.dart';
import '../blocs/admin_users/admin_users_state.dart';
import '../models/admin_user_info.dart';
import '../widgets/admin_layout.dart';

class AdminUserDetailScreen extends StatefulWidget {
  final String adminUserId;

  const AdminUserDetailScreen({super.key, required this.adminUserId});

  @override
  State<AdminUserDetailScreen> createState() => _AdminUserDetailScreenState();
}

class _AdminUserDetailScreenState extends State<AdminUserDetailScreen> {
  bool? _filterSuccess;

  @override
  void initState() {
    super.initState();
    // Load admin user detail when screen initializes
    context.read<AdminUsersBloc>().add(LoadAdminUserDetail(widget.adminUserId));
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/admin-users',
      child: BlocBuilder<AdminUsersBloc, AdminUsersState>(
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

  Widget _buildHeader(BuildContext context, AdminUsersState state) {
    String title = 'Admin User Detail';
    if (state is AdminUserDetailLoaded) {
      title = state.adminUser.username;
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/admin-users'),
            tooltip: 'Back to Admin Users',
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context
                  .read<AdminUsersBloc>()
                  .add(LoadAdminUserDetail(widget.adminUserId));
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, AdminUsersState state) {
    if (state is AdminUserDetailLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is AdminUsersError) {
      return _buildError(context, state.message);
    }

    if (state is AdminUserDetailLoaded) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildUserInfoCard(context, state.adminUser)),
                const SizedBox(width: 24),
                Expanded(child: _buildLoginStatsCard(context, state)),
              ],
            ),
            const SizedBox(height: 24),
            _buildLoginHistoryCard(context, state),
          ],
        ),
      );
    }

    // Initial state - show loading
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildUserInfoCard(BuildContext context, AdminUserInfo adminUser) {
    final dateFormat = DateFormat('MMMM d, yyyy \'at\' HH:mm');

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  child: Text(
                    adminUser.username[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      adminUser.username,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Administrator',
                        style: TextStyle(
                          color: Colors.blue[900],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            _buildInfoRow(
              context,
              icon: Icons.calendar_today,
              label: 'Created',
              value: dateFormat.format(adminUser.createdAt),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              icon: Icons.login,
              label: 'Last Login',
              value: adminUser.lastLoginAt != null
                  ? dateFormat.format(adminUser.lastLoginAt!)
                  : 'Never logged in',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              context,
              icon: Icons.fingerprint,
              label: 'User ID',
              value: adminUser.id,
              isMonospace: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    bool isMonospace = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontFamily: isMonospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginStatsCard(
    BuildContext context,
    AdminUserDetailLoaded state,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Login Statistics',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    label: 'Total Logins',
                    value: '${state.adminUser.loginCount}',
                    icon: Icons.login,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    context,
                    label: 'Successful',
                    value: '${state.totalLogins}',
                    icon: Icons.check_circle,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    context,
                    label: 'Failed',
                    value: '${state.failedLogins}',
                    icon: Icons.cancel,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatItem(
                    context,
                    label: 'Suspicious',
                    value: '${state.suspiciousAttempts}',
                    icon: Icons.warning,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginHistoryCard(
    BuildContext context,
    AdminUserDetailLoaded state,
  ) {
    final dateFormat = DateFormat('MMM d, yyyy HH:mm:ss');
    final filteredHistory = _filterSuccess == null
        ? state.loginHistory
        : state.loginHistory.where((a) => a.success == _filterSuccess).toList();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Login History',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _filterSuccess == null,
                      onSelected: (_) {
                        setState(() => _filterSuccess = null);
                      },
                    ),
                    FilterChip(
                      label: const Text('Successful'),
                      selected: _filterSuccess == true,
                      onSelected: (_) {
                        setState(() => _filterSuccess = true);
                      },
                    ),
                    FilterChip(
                      label: const Text('Failed'),
                      selected: _filterSuccess == false,
                      onSelected: (_) {
                        setState(() => _filterSuccess = false);
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            filteredHistory.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No login attempts found',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
                  )
                : DataTable(
                    columns: const [
                      DataColumn(label: Text('Timestamp')),
                      DataColumn(label: Text('Status')),
                      DataColumn(label: Text('IP Address')),
                      DataColumn(label: Text('User Agent')),
                    ],
                    rows: filteredHistory.take(50).map((attempt) {
                      return DataRow(
                        cells: [
                          DataCell(Text(dateFormat.format(attempt.timestamp))),
                          DataCell(_buildLoginStatusBadge(context, attempt)),
                          DataCell(
                            Text(
                              attempt.ipAddress ?? 'Unknown',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                          DataCell(
                            SizedBox(
                              width: 200,
                              child: Tooltip(
                                message: attempt.userAgent ?? 'Unknown',
                                child: Text(
                                  attempt.userAgent ?? 'Unknown',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginStatusBadge(BuildContext context, LoginAttempt attempt) {
    if (attempt.isSuspicious) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning, size: 14, color: Colors.orange[900]),
            const SizedBox(width: 4),
            Text(
              'Suspicious',
              style: TextStyle(
                color: Colors.orange[900],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (attempt.success) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Success',
          style: TextStyle(
            color: Colors.green[900],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Tooltip(
      message: attempt.failureReason ?? 'Authentication failed',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Failed',
          style: TextStyle(
            color: Colors.red[900],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
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
              'Failed to load admin user details',
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => context.go('/admin-users'),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
                const SizedBox(width: 16),
                FilledButton.icon(
                  onPressed: () {
                    context
                        .read<AdminUsersBloc>()
                        .add(LoadAdminUserDetail(widget.adminUserId));
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
