import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

import '../src/components/layout.dart';
import '../src/components/package_card.dart';
import '../src/services/api_client.dart';

/// Home page showing list of packages
@client
class HomePage extends StatefulComponent {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _loading = true;
  String? _error;
  PackageListResponse? _response;

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages() async {
    final apiClient = ApiClient(baseUrl: '');
    try {
      final response = await apiClient.listPackages();
      setState(() {
        _response = response;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    } finally {
      apiClient.dispose();
    }
  }

  @override
  Component build(BuildContext context) {
    if (_loading) {
      return Layout(
        children: [
          _buildHero(),
          _buildLoadingState(),
        ],
      );
    }

    if (_error != null) {
      return Layout(
        children: [
          _buildHero(),
          _buildErrorState(_error!),
        ],
      );
    }

    return Layout(
      children: [
        _buildHero(),
        _buildPackageList(_response!),
      ],
    );
  }

  Component _buildHero() {
    return section(
      classes: 'text-center mb-12',
      [
        h1(
          classes: 'text-4xl font-bold text-gray-900 mb-4',
          [Component.text('Dart Package Registry')],
        ),
        p(
          classes: 'text-lg text-gray-600 max-w-2xl mx-auto',
          [Component.text('A private Dart package repository for your team. Browse, search, and manage your packages.')],
        ),
        // Search box
        div(
          classes: 'mt-8 max-w-xl mx-auto',
          [
            form(
              attributes: {'action': '/search', 'method': 'get'},
              [
                div(
                  classes: 'flex rounded-lg shadow-sm',
                  [
                    input(
                      type: InputType.text,
                      name: 'q',
                      classes: 'flex-1 px-4 py-3 border border-gray-300 rounded-l-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none',
                      attributes: {'placeholder': 'Search packages...'},
                    ),
                    button(
                      type: ButtonType.submit,
                      classes: 'px-6 py-3 bg-blue-600 text-white font-medium rounded-r-lg hover:bg-blue-700 transition-colors',
                      [Component.text('Search')],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildLoadingState() {
    return div(
      classes: 'grid gap-4 md:grid-cols-2 lg:grid-cols-3',
      [
        for (var i = 0; i < 6; i++)
          div(
            classes: 'bg-white rounded-lg border border-gray-200 p-6 animate-pulse',
            [
              div(classes: 'h-6 bg-gray-200 rounded w-1/2 mb-3', []),
              div(classes: 'h-4 bg-gray-200 rounded w-full mb-2', []),
              div(classes: 'h-4 bg-gray-200 rounded w-3/4', []),
            ],
          ),
      ],
    );
  }

  Component _buildErrorState(String error) {
    return div(
      classes: 'text-center py-12',
      [
        div(
          classes: 'inline-block p-4 bg-red-50 rounded-full mb-4',
          [
            span(classes: 'text-red-500 text-4xl', [Component.text('!')]),
          ],
        ),
        h2(
          classes: 'text-xl font-semibold text-gray-900 mb-2',
          [Component.text('Failed to load packages')],
        ),
        p(
          classes: 'text-gray-600 mb-4',
          [Component.text(error)],
        ),
        a(
          href: '/',
          classes: 'text-blue-600 hover:text-blue-800',
          [Component.text('Try again')],
        ),
      ],
    );
  }

  Component _buildPackageList(PackageListResponse response) {
    if (response.packages.isEmpty) {
      return div(
        classes: 'text-center py-12',
        [
          div(
            classes: 'inline-block p-4 bg-gray-100 rounded-full mb-4',
            [
              span(classes: 'text-gray-400 text-4xl', [RawText('&#x1F4E6;')]),
            ],
          ),
          h2(
            classes: 'text-xl font-semibold text-gray-900 mb-2',
            [Component.text('No packages yet')],
          ),
          p(
            classes: 'text-gray-600',
            [Component.text('Publish your first package to get started.')],
          ),
        ],
      );
    }

    return Component.fragment([
      // Section header
      div(
        classes: 'flex items-center justify-between mb-6',
        [
          h2(
            classes: 'text-2xl font-bold text-gray-900',
            [Component.text('All Packages')],
          ),
          span(
            classes: 'text-gray-500',
            [Component.text('${response.total} package${response.total != 1 ? "s" : ""}')],
          ),
        ],
      ),
      // Package grid
      div(
        classes: 'grid gap-4 md:grid-cols-2 lg:grid-cols-3',
        [
          for (final pkg in response.packages)
            PackageCard(packageInfo: pkg),
        ],
      ),
      // Pagination
      if (response.totalPages > 1)
        _buildPagination(response),
    ]);
  }

  Component _buildPagination(PackageListResponse response) {
    return div(
      classes: 'flex justify-center items-center space-x-2 mt-8',
      [
        if (response.hasPrevPage)
          a(
            href: '/?page=${response.page - 1}',
            classes: 'px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50',
            [Component.text('Previous')],
          ),
        span(
          classes: 'px-4 py-2 text-gray-600',
          [Component.text('Page ${response.page} of ${response.totalPages}')],
        ),
        if (response.hasNextPage)
          a(
            href: '/?page=${response.page + 1}',
            classes: 'px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50',
            [Component.text('Next')],
          ),
      ],
    );
  }
}
