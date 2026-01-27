import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'router.dart';
import 'services/auth_service.dart';
import 'blocs/dashboard/dashboard_bloc.dart';
import 'blocs/packages/packages_bloc.dart';
import 'blocs/users/users_bloc.dart';
import 'blocs/admin_users/admin_users_bloc.dart';
import 'blocs/config/config_bloc.dart';

/// Root application widget that provides all BLoCs.
class RepubAdminApp extends StatelessWidget {
  const RepubAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => AuthBloc()),
        BlocProvider(create: (context) => DashboardBloc()),
        BlocProvider(create: (context) => PackagesBloc()),
        BlocProvider(create: (context) => UsersBloc()),
        BlocProvider(create: (context) => AdminUsersBloc()),
        BlocProvider(create: (context) => ConfigBloc()),
      ],
      child: const RepubAdminRouterApp(),
    );
  }
}

/// Application widget with MaterialApp.router configured.
class RepubAdminRouterApp extends StatelessWidget {
  const RepubAdminRouterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = createRouter(context);

    return MaterialApp.router(
      title: 'Repub Admin',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
