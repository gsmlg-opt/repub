import 'package:flutter/material.dart';
import '../widgets/admin_layout.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/admin-users',
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.admin_panel_settings, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Admin Users',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('Feature in development',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
