import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminLayout extends StatelessWidget {
  final Widget child;
  final String currentPath;

  const AdminLayout({
    super.key,
    required this.child,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isLargeScreen = constraints.maxWidth >= 900;

        if (isLargeScreen) {
          // Desktop layout with permanent sidebar
          return Scaffold(
            body: Row(
              children: [
                _buildSidebar(context, isPermanent: true),
                Expanded(
                  child: Column(
                    children: [
                      _buildAppBar(context, showMenuButton: false),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          // Mobile layout with drawer
          return Scaffold(
            appBar: _buildAppBar(context, showMenuButton: true),
            drawer: Drawer(
              child: _buildSidebar(context, isPermanent: false),
            ),
            body: child,
          );
        }
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, {required bool showMenuButton}) {
    return AppBar(
      leading: showMenuButton ? null : const SizedBox.shrink(),
      automaticallyImplyLeading: showMenuButton,
      title: const Text('Repub Admin'),
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
    );
  }

  Widget _buildSidebar(BuildContext context, {required bool isPermanent}) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: isPermanent
            ? Border(right: BorderSide(color: Theme.of(context).dividerColor))
            : null,
      ),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Repub Admin',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Package Registry Administration',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          _buildNavItem(
            context,
            icon: Icons.dashboard,
            title: 'Dashboard',
            path: '/',
            isPermanent: isPermanent,
          ),
          _buildNavItem(
            context,
            icon: Icons.inventory,
            title: 'Local Packages',
            path: '/packages/local',
            isPermanent: isPermanent,
          ),
          _buildNavItem(
            context,
            icon: Icons.cached,
            title: 'Cached Packages',
            path: '/packages/cached',
            isPermanent: isPermanent,
          ),
          const Divider(),
          _buildNavItem(
            context,
            icon: Icons.settings,
            title: 'Site Configuration',
            path: '/config',
            isPermanent: isPermanent,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('View Registry'),
            onTap: () {
              // Navigate to main registry (outside admin)
              // Note: In production, use url_launcher or JS interop to open in new tab
              if (!isPermanent) {
                Navigator.pop(context);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String path,
    required bool isPermanent,
  }) {
    final isSelected = currentPath == path;

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: isSelected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      onTap: () {
        if (!isPermanent) {
          Navigator.pop(context);
        }
        context.go(path);
      },
    );
  }
}
