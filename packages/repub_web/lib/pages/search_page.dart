import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

import '../src/components/layout.dart';
import '../src/components/package_card.dart';
import '../src/services/api_client.dart';

/// Search page for finding packages
@client
class SearchPage extends StatefulComponent {
  final String query;

  const SearchPage({required this.query, super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  bool _loading = false;
  String? _error;
  PackageListResponse? _response;

  @override
  void initState() {
    super.initState();
    if (component.query.isNotEmpty) {
      _search();
    }
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final apiClient = ApiClient();
    try {
      final response = await apiClient.searchPackages(component.query);
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
    if (component.query.isEmpty) {
      return Layout(children: [_buildEmptySearch()]);
    }

    if (_loading) {
      return Layout(
        children: [_buildSearchHeader(), _buildLoadingState()],
      );
    }

    if (_error != null) {
      return Layout(
        children: [_buildSearchHeader(), _buildErrorState(_error!)],
      );
    }

    return Layout(
      children: [_buildSearchHeader(), _buildSearchResults(_response!)],
    );
  }

  Component _buildSearchHeader() {
    return section(
      classes: 'mb-8',
      [
        h1(
          classes: 'text-3xl font-bold text-gray-900 mb-6',
          [Component.text('Search Packages')],
        ),
        form(
          attributes: {'action': '/search', 'method': 'get'},
          [
            div(
              classes: 'flex rounded-lg shadow-sm max-w-2xl',
              [
                input(
                  type: InputType.text,
                  name: 'q',
                  classes: 'flex-1 px-4 py-3 border border-gray-300 rounded-l-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none',
                  attributes: {
                    'placeholder': 'Search packages...',
                    'value': component.query,
                  },
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
    );
  }

  Component _buildEmptySearch() {
    return Component.fragment([
      section(
        classes: 'mb-8',
        [
          h1(
            classes: 'text-3xl font-bold text-gray-900 mb-6',
            [Component.text('Search Packages')],
          ),
          form(
            attributes: {'action': '/search', 'method': 'get'},
            [
              div(
                classes: 'flex rounded-lg shadow-sm max-w-2xl',
                [
                  input(
                    type: InputType.text,
                    name: 'q',
                    classes: 'flex-1 px-4 py-3 border border-gray-300 rounded-l-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none',
                    attributes: {'placeholder': 'Search packages...', 'autofocus': 'true'},
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
      div(
        classes: 'text-center py-12',
        [
          div(
            classes: 'inline-block p-4 bg-gray-100 rounded-full mb-4',
            [span(classes: 'text-4xl', [RawText('&#x1F50D;')])],
          ),
          h2(
            classes: 'text-xl font-semibold text-gray-900 mb-2',
            [Component.text('Enter a search term')],
          ),
          p(
            classes: 'text-gray-600',
            [Component.text('Search by package name or keywords in the description.')],
          ),
        ],
      ),
    ]);
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
          [span(classes: 'text-red-500 text-4xl', [Component.text('!')])],
        ),
        h2(
          classes: 'text-xl font-semibold text-gray-900 mb-2',
          [Component.text('Search failed')],
        ),
        p(
          classes: 'text-gray-600 mb-4',
          [Component.text(error)],
        ),
      ],
    );
  }

  Component _buildSearchResults(PackageListResponse response) {
    if (response.packages.isEmpty) {
      return div(
        classes: 'text-center py-12',
        [
          div(
            classes: 'inline-block p-4 bg-gray-100 rounded-full mb-4',
            [span(classes: 'text-4xl', [RawText('&#x1F50D;')])],
          ),
          h2(
            classes: 'text-xl font-semibold text-gray-900 mb-2',
            [Component.text('No packages found')],
          ),
          p(
            classes: 'text-gray-600 mb-6',
            [Component.text('No packages match "${component.query}". Try a different search term.')],
          ),
          a(
            href: '/',
            classes: 'text-blue-600 hover:text-blue-800',
            [Component.text('Browse all packages')],
          ),
        ],
      );
    }

    return Component.fragment([
      // Results header
      div(
        classes: 'flex items-center justify-between mb-6',
        [
          h2(
            classes: 'text-xl font-semibold text-gray-900',
            [Component.text('Results for "${component.query}"')],
          ),
          span(
            classes: 'text-gray-500',
            [Component.text('${response.total} result${response.total != 1 ? "s" : ""}')],
          ),
        ],
      ),
      // Results grid
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
            href: '/search?q=${Uri.encodeComponent(component.query)}&page=${response.page - 1}',
            classes: 'px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50',
            [Component.text('Previous')],
          ),
        span(
          classes: 'px-4 py-2 text-gray-600',
          [Component.text('Page ${response.page} of ${response.totalPages}')],
        ),
        if (response.hasNextPage)
          a(
            href: '/search?q=${Uri.encodeComponent(component.query)}&page=${response.page + 1}',
            classes: 'px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50',
            [Component.text('Next')],
          ),
      ],
    );
  }
}
