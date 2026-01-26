import 'package:flutter/material.dart';
import '../widgets/admin_layout.dart';

class CachedPackagesScreen extends StatelessWidget {
  const CachedPackagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/packages/cached',
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cached, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('Cached Packages',
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
