import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../blocs/users/users_bloc.dart';
import '../blocs/users/users_event.dart';
import '../blocs/users/users_state.dart';
import '../models/user_info.dart';
import '../widgets/admin_layout.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool? _activeFilter;

  @override
  void initState() {
    super.initState();
    // Load users when screen initializes
    context.read<UsersBloc>().add(const LoadUsers());
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
      context.read<UsersBloc>().add(SearchUsers(query));
    });
  }

  void _onFilterChanged(bool? activeOnly) {
    setState(() {
      _activeFilter = activeOnly;
    });
    context.read<UsersBloc>().add(LoadUsers(
          search:
              _searchController.text.isNotEmpty ? _searchController.text : null,
          activeOnly: activeOnly,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/users',
      child: BlocConsumer<UsersBloc, UsersState>(
        listener: (context, state) {
          if (state is UserOperationSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is UserOperationError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is UserTokensLoaded) {
            _showTokensDialog(context, state);
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

  Widget _buildHeader(BuildContext context, UsersState state) {
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
                'User Management',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  if (state is UsersLoaded)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Chip(
                        label: Text('${state.total} users'),
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      context.read<UsersBloc>().add(LoadUsers(
                            search: _searchController.text.isNotEmpty
                                ? _searchController.text
                                : null,
                            activeOnly: _activeFilter,
                          ));
                    },
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 400,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by email...',
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
              const SizedBox(width: 16),
              _buildFilterChips(context),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        FilterChip(
          label: const Text('All'),
          selected: _activeFilter == null,
          onSelected: (_) => _onFilterChanged(null),
        ),
        FilterChip(
          label: const Text('Active'),
          selected: _activeFilter == true,
          onSelected: (_) => _onFilterChanged(true),
        ),
        FilterChip(
          label: const Text('Inactive'),
          selected: _activeFilter == false,
          onSelected: (_) => _onFilterChanged(false),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, UsersState state) {
    if (state is UsersLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is UsersError) {
      return _buildError(context, state.message);
    }

    if (state is UsersLoaded) {
      if (state.users.isEmpty) {
        return _buildEmptyState(context, state.searchQuery);
      }
      return _buildUsersTable(context, state);
    }

    if (state is UserOperationInProgress) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('${_capitalizeFirst(state.operation)} user...'),
          ],
        ),
      );
    }

    // Initial state - reload
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildUsersTable(BuildContext context, UsersLoaded state) {
    final dateFormat = DateFormat('MMM d, yyyy');

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              elevation: 2,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Registered')),
                  DataColumn(label: Text('Tokens'), numeric: true),
                  DataColumn(label: Text('Actions')),
                ],
                rows: state.users.map((user) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          user.email,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      DataCell(_buildStatusBadge(context, user)),
                      DataCell(Text(dateFormat.format(user.createdAt))),
                      DataCell(
                        InkWell(
                          onTap: () {
                            context
                                .read<UsersBloc>()
                                .add(ViewUserTokens(user.id));
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${user.tokenCount}'),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.visibility,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(_buildActionButtons(context, user)),
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

  Widget _buildStatusBadge(BuildContext context, UserInfo user) {
    if (user.isActive) {
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Inactive',
        style: TextStyle(
          color: Colors.grey[700],
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, UserInfo user) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.vpn_key, size: 20),
          onPressed: () {
            context.read<UsersBloc>().add(ViewUserTokens(user.id));
          },
          tooltip: 'View tokens',
        ),
        IconButton(
          icon: Icon(
            user.isActive ? Icons.block : Icons.check_circle,
            size: 20,
          ),
          onPressed: () => _showToggleStatusDialog(context, user),
          tooltip: user.isActive ? 'Deactivate' : 'Activate',
          color: user.isActive ? Colors.orange : Colors.green,
        ),
        IconButton(
          icon: const Icon(Icons.delete, size: 20),
          onPressed: () => _showDeleteDialog(context, user),
          tooltip: 'Delete user',
          color: Colors.red,
        ),
      ],
    );
  }

  Widget _buildPaginationControls(BuildContext context, UsersLoaded state) {
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
                    context.read<UsersBloc>().add(
                          LoadUsers(
                            page: state.page - 1,
                            limit: state.limit,
                            search: state.searchQuery,
                            activeOnly: state.activeOnly,
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
                    context.read<UsersBloc>().add(
                          LoadUsers(
                            page: state.page + 1,
                            limit: state.limit,
                            search: state.searchQuery,
                            activeOnly: state.activeOnly,
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
                  : Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              searchQuery != null && searchQuery.isNotEmpty
                  ? 'No users found matching "$searchQuery"'
                  : 'No users registered',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              searchQuery != null && searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Users who register will appear here',
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
              'Failed to load users',
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
                context.read<UsersBloc>().add(const LoadUsers());
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  void _showToggleStatusDialog(BuildContext context, UserInfo user) {
    final action = user.isActive ? 'deactivate' : 'activate';

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(
              user.isActive ? Icons.block : Icons.check_circle,
              color: user.isActive ? Colors.orange[700] : Colors.green[700],
            ),
            const SizedBox(width: 8),
            Text('${_capitalizeFirst(action)} User'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to $action "${user.email}"?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              user.isActive
                  ? 'Deactivated users cannot login and their tokens become invalid.'
                  : 'This will restore the user\'s access to the registry.',
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
              backgroundColor: user.isActive ? Colors.orange : Colors.green,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (user.isActive) {
                context.read<UsersBloc>().add(DeactivateUser(user.id));
              } else {
                context.read<UsersBloc>().add(ActivateUser(user.id));
              }
            },
            child: Text(_capitalizeFirst(action)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, UserInfo user) {
    final TextEditingController confirmController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red[700]),
            const SizedBox(width: 8),
            const Text('Delete User'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to delete "${user.email}"?',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              'This will permanently delete the user and all their tokens. '
              'This action cannot be undone.',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              decoration: InputDecoration(
                labelText: 'Type "${user.email}" to confirm',
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
              if (confirmController.text == user.email) {
                Navigator.of(dialogContext).pop();
                context.read<UsersBloc>().add(DeleteUser(user.id));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Email does not match'),
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

  void _showTokensDialog(BuildContext context, UserTokensLoaded state) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Colors.blue),
            SizedBox(width: 8),
            Text('User Tokens'),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: state.tokens.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'This user has no active tokens.',
                    textAlign: TextAlign.center,
                  ),
                )
              : SingleChildScrollView(
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('Label')),
                      DataColumn(label: Text('Scopes')),
                      DataColumn(label: Text('Created')),
                    ],
                    rows: state.tokens.map((token) {
                      return DataRow(
                        cells: [
                          DataCell(Text(token.label)),
                          DataCell(
                            Wrap(
                              spacing: 4,
                              children: token.scopes.map((scope) {
                                return Chip(
                                  label: Text(
                                    scope,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                );
                              }).toList(),
                            ),
                          ),
                          DataCell(
                            Text(
                              DateFormat('MMM d, yyyy').format(token.createdAt),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
