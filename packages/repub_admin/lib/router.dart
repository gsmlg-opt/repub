import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'screens/dashboard_screen.dart';
import 'screens/local_packages_screen.dart';
import 'screens/cached_packages_screen.dart';
import 'screens/site_config_screen.dart';
import 'screens/users_screen.dart';
import 'screens/admin_users_screen.dart';
import 'screens/admin_user_detail_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

/// Creates the GoRouter configuration for the admin app.
GoRouter createRouter(BuildContext context) {
  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final authState = context.read<AuthBloc>().state;
      final isAuthenticated = authState.isAuthenticated;
      final isLoggingIn = state.matchedLocation == '/login';

      // If loading, allow navigation to continue
      if (authState is AuthInitial || authState is AuthLoading) {
        return null;
      }

      // If not authenticated and not on login page, redirect to login
      if (!isAuthenticated && !isLoggingIn) {
        return '/login';
      }

      // If authenticated and on login page, redirect to dashboard
      if (isAuthenticated && isLoggingIn) {
        return '/';
      }

      return null;
    },
    refreshListenable: GoRouterRefreshNotifier(context.read<AuthBloc>()),
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
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
}

/// Listens to AuthBloc changes and notifies GoRouter to refresh.
class GoRouterRefreshNotifier extends ChangeNotifier {
  GoRouterRefreshNotifier(AuthBloc authBloc) {
    _subscription = authBloc.stream.listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<AuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
