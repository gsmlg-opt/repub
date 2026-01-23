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
  bool _localLoading = false;
  bool _upstreamLoading = false;
  String? _error;
  PackageListResponse? _localResponse;
  PackageListResponse? _upstreamResponse;

  @override
  void initState() {
    super.initState();
    if (component.query.isNotEmpty) {
      _search();
    }
  }

  Future<void> _search() async {
    // Search local packages first
    setState(() {
      _localLoading = true;
      _upstreamLoading = true;
      _error = null;
      _localResponse = null;
      _upstreamResponse = null;
    });

    final apiClient = ApiClient();
    try {
      // Fetch local results
      final localResponse = await apiClient.searchPackages(component.query);
      setState(() {
        _localResponse = localResponse;
        _localLoading = false;
      });

      // Then fetch upstream results asynchronously
      _searchUpstream(apiClient);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _localLoading = false;
        _upstreamLoading = false;
      });
      apiClient.dispose();
    }
  }

  Future<void> _searchUpstream(ApiClient apiClient) async {
    try {
      final upstreamResponse = await apiClient.searchPackagesUpstream(component.query);
      setState(() {
        _upstreamResponse = upstreamResponse;
        _upstreamLoading = false;
      });
    } catch (e) {
      // Silently fail upstream search - not critical
      setState(() {
        _upstreamLoading = false;
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

    if (_localLoading) {
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
      children: [
        _buildSearchHeader(),
        _buildSearchResults(_localResponse!, _upstreamResponse, _upstreamLoading),
      ],
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

  Component _buildSearchResults(
    PackageListResponse localResponse,
    PackageListResponse? upstreamResponse,
    bool upstreamLoading,
  ) {
    final hasLocalResults = localResponse.packages.isNotEmpty;
    final hasUpstreamResults = upstreamResponse?.packages.isNotEmpty ?? false;

    return Component.fragment([
      // Local packages section
      div(
        classes: 'mb-8',
        [
          div(
            classes: 'flex items-center justify-between mb-6',
            [
              h2(
                classes: 'text-xl font-semibold text-gray-900',
                [Component.text('Local Packages')],
              ),
              span(
                classes: 'text-gray-500',
                [Component.text('${localResponse.total} result${localResponse.total != 1 ? "s" : ""}')],
              ),
            ],
          ),
          if (hasLocalResults)
            div(
              classes: 'grid gap-4 md:grid-cols-2 lg:grid-cols-3',
              [
                for (final pkg in localResponse.packages)
                  PackageCard(packageInfo: pkg),
              ],
            )
          else
            div(
              classes: 'text-center py-8 bg-gray-50 rounded-lg',
              [
                p(
                  classes: 'text-gray-600',
                  [Component.text('No local packages found')],
                ),
              ],
            ),
          if (localResponse.totalPages > 1)
            _buildPagination(localResponse),
        ],
      ),

      // Upstream packages section
      div(
        classes: 'mb-8',
        [
          div(
            classes: 'flex items-center justify-between mb-6',
            [
              h2(
                classes: 'text-xl font-semibold text-gray-900',
                [Component.text('Packages from pub.dev')],
              ),
              if (upstreamLoading)
                span(
                  classes: 'text-gray-500',
                  [Component.text('Loading...')],
                )
              else if (hasUpstreamResults)
                span(
                  classes: 'text-gray-500',
                  [Component.text('${upstreamResponse!.total} result${upstreamResponse.total != 1 ? "s" : ""}')],
                ),
            ],
          ),
          if (upstreamLoading)
            _buildLoadingState()
          else if (hasUpstreamResults)
            div(
              classes: 'grid gap-4 md:grid-cols-2 lg:grid-cols-3',
              [
                for (final pkg in upstreamResponse!.packages)
                  PackageCard(packageInfo: pkg, isUpstream: true),
              ],
            )
          else
            div(
              classes: 'text-center py-8 bg-gray-50 rounded-lg',
              [
                p(
                  classes: 'text-gray-600',
                  [Component.text('No packages found on pub.dev')],
                ),
              ],
            ),
        ],
      ),
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
