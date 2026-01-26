import 'package:flutter/material.dart';
import '../widgets/admin_layout.dart';

class LocalPackagesScreen extends StatelessWidget {
  const LocalPackagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/packages/local',
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Local Packages',
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
