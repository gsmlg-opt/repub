import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'screens/dashboard_screen.dart';
import 'screens/local_packages_screen.dart';
import 'screens/cached_packages_screen.dart';
import 'screens/site_config_screen.dart';
import 'screens/users_screen.dart';
import 'screens/admin_users_screen.dart';
import 'screens/admin_user_detail_screen.dart';

void main() {
  usePathUrlStrategy(); // Use HTML5 path-based routing instead of hash
  runApp(const ProviderScope(child: RepubAdminApp()));
}

class RepubAdminApp extends StatelessWidget {
  const RepubAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Repub Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DashboardScreen(),
    ),
    GoRoute(
      path: '/packages/local',
      builder: (context, state) => const LocalPackagesScreen(),
    ),
    GoRoute(
      path: '/packages/cached',
      builder: (context, state) => const CachedPackagesScreen(),
    ),
    GoRoute(
      path: '/config',
      builder: (context, state) => const SiteConfigScreen(),
    ),
    GoRoute(
      path: '/users',
      builder: (context, state) => const UsersScreen(),
    ),
    GoRoute(
      path: '/admin-users',
      builder: (context, state) => const AdminUsersScreen(),
    ),
    GoRoute(
      path: '/admin-users/:id',
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return AdminUserDetailScreen(adminUserId: id);
      },
    ),
  ],
);
