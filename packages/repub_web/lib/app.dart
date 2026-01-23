import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'pages/account/account_page.dart';
import 'pages/account/tokens_page.dart';
import 'pages/admin/admin_cached_packages.dart';
import 'pages/admin/admin_local_packages.dart';
import 'pages/admin/admin_page.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/register_page.dart';
import 'pages/docs_page.dart';
import 'pages/home_page.dart';
import 'pages/package_page.dart';
import 'pages/search_page.dart';
import 'pages/upstream_package_page.dart';

@client
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) {
    return Router(
      routes: [
        Route(
          path: '/',
          title: 'Repub - Dart Package Registry',
          builder: (context, state) => const HomePage(),
        ),
        Route(
          path: '/packages/:name',
          title: 'Package Details',
          builder: (context, state) => PackagePage(
            packageName: state.params['name']!,
          ),
        ),
        Route(
          path: '/search',
          title: 'Search Packages',
          builder: (context, state) => SearchPage(
            query: state.queryParams['q'] ?? '',
          ),
        ),
        Route(
          path: '/upstream-packages/:name',
          title: 'Upstream Package Details',
          builder: (context, state) => UpstreamPackagePage(
            packageName: state.params['name']!,
          ),
        ),
        Route(
          path: '/docs',
          title: 'Documentation - Repub',
          builder: (context, state) => const DocsPage(),
        ),
        // Auth routes
        Route(
          path: '/login',
          title: 'Sign In - Repub',
          builder: (context, state) => const LoginPage(),
        ),
        Route(
          path: '/register',
          title: 'Register - Repub',
          builder: (context, state) => const RegisterPage(),
        ),
        // Account routes
        Route(
          path: '/account',
          title: 'Account - Repub',
          builder: (context, state) => const AccountPage(),
        ),
        Route(
          path: '/account/tokens',
          title: 'API Tokens - Repub',
          builder: (context, state) => const TokensPage(),
        ),
        // Admin routes
        Route(
          path: '/admin',
          title: 'Admin - Repub',
          builder: (context, state) => const AdminPage(),
        ),
        Route(
          path: '/admin/packages/local',
          title: 'Local Packages - Admin',
          builder: (context, state) => const AdminLocalPackagesPage(),
        ),
        Route(
          path: '/admin/packages/cached',
          title: 'Cached Packages - Admin',
          builder: (context, state) => const AdminCachedPackagesPage(),
        ),
      ],
    );
  }
}
