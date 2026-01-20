import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'pages/home_page.dart';
import 'pages/package_page.dart';
import 'pages/search_page.dart';

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
      ],
    );
  }
}
