import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'router.dart';
import 'services/auth_service.dart';

/// Root application widget that provides the AuthBloc.
class RepubAdminApp extends StatelessWidget {
  const RepubAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => AuthBloc(),
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
