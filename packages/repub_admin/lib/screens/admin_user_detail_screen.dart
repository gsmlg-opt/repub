import 'package:flutter/material.dart';
import '../widgets/admin_layout.dart';

class AdminUserDetailScreen extends StatelessWidget {
  final String adminUserId;
  const AdminUserDetailScreen({super.key, required this.adminUserId});

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/admin-users',
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Admin User Details',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text('ID: $adminUserId', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
