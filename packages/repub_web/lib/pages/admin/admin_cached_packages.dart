import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:repub_model/repub_model_web.dart';
import 'package:web/web.dart' as web;

import '../../src/components/admin_layout.dart';
import '../../src/services/admin_api_client.dart';
import '../../src/services/api_client.dart';

/// Admin page for managing cached packages.
@client
class AdminCachedPackagesPage extends StatefulComponent {
  const AdminCachedPackagesPage({super.key});

  @override
  State<AdminCachedPackagesPage> createState() =>
      _AdminCachedPackagesPageState();
}

class _AdminCachedPackagesPageState extends State<AdminCachedPackagesPage> {
  bool _loading = true;
  String? _error;
  PackageListResponse? _response;
  String? _actionMessage;
  bool _actionError = false;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadPackages();
  }

  Future<void> _loadPackages({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = AdminApiClient();
    try {
      final response = await client.listCachedPackages(page: page);
      setState(() {
        _response = response;
        _loading = false;
      });
    } catch (e) {
      if (e is AdminApiException &&
          (e.statusCode == 401 || e.statusCode == 403)) {
        web.window.location.href = '/admin';
        return;
      }
      setState(() {
        _error = e is AdminApiException ? e.message : e.toString();
        _loading = false;
      });
    } finally {
      client.dispose();
    }
  }

  Future<void> _deletePackage(String name) async {
    final confirmed = web.window
        .confirm('Are you sure you want to delete cached package "$name"?');
    if (!confirmed) return;

    final client = AdminApiClient();
    try {
      final result = await client.deletePackage(name);
      setState(() {
        _actionMessage = result.message;
        _actionError = false;
      });
      await _loadPackages(page: _response?.page ?? 1);
    } catch (e) {
      setState(() {
        _actionMessage = e is AdminApiException ? e.message : e.toString();
        _actionError = true;
      });
    } finally {
      client.dispose();
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = web.window.confirm(
      'Are you sure you want to clear ALL cached packages? This action cannot be undone.',
    );
    if (!confirmed) return;

    setState(() {
      _clearing = true;
    });

    final client = AdminApiClient();
    try {
      final result = await client.clearCache();
      setState(() {
        _actionMessage = result.message;
        _actionError = false;
        _clearing = false;
      });
      await _loadPackages();
    } catch (e) {
      setState(() {
        _actionMessage = e is AdminApiException ? e.message : e.toString();
        _actionError = true;
        _clearing = false;
      });
    } finally {
      client.dispose();
    }
  }

  @override
  Component build(BuildContext context) {
    return AdminLayout(
      currentPath: '/admin/packages/cached',
      children: [
        // Action message
        if (_actionMessage != null)
          div(
            classes: _actionError
                ? 'mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm'
                : 'mb-4 p-3 bg-green-50 border border-green-200 rounded-lg text-green-700 text-sm',
            [
              div(
                classes: 'flex justify-between items-center',
                [
                  Component.text(_actionMessage!),
                  button(
                    type: ButtonType.button,
                    classes: 'text-gray-400 hover:text-gray-600',
                    events: {
                      'click': (_) => setState(() => _actionMessage = null)
                    },
                    [Component.text('x')],
                  ),
                ],
              ),
            ],
          ),
        // Clear all cache button
        if (_response != null && _response!.packages.isNotEmpty)
          div(
            classes: 'mb-4 flex justify-end',
            [
              button(
                type: ButtonType.button,
                classes: _clearing
                    ? 'px-4 py-2 bg-gray-400 text-white rounded-lg cursor-not-allowed'
                    : 'px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700 transition-colors',
                events: {'click': (_) => _clearAllCache()},
                [Component.text(_clearing ? 'Clearing...' : 'Clear All Cache')],
              ),
            ],
          ),
        // Content
        if (_loading)
          _buildLoadingState()
        else if (_error != null)
          _buildErrorState(_error!)
        else if (_response != null)
          _buildPackageList(_response!),
      ],
    );
  }

  Component _buildLoadingState() {
    return div(
      classes: 'bg-white rounded-lg shadow',
      [
        div(
          classes: 'p-6 animate-pulse',
          [
            for (var i = 0; i < 5; i++)
              div(
                classes:
                    'flex items-center justify-between py-4 border-b border-gray-100 last:border-0',
                [
                  div([
                    div(classes: 'h-5 bg-gray-200 rounded w-40 mb-2', []),
                    div(classes: 'h-4 bg-gray-200 rounded w-24', []),
                  ]),
                  div(classes: 'h-8 bg-gray-200 rounded w-20', []),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Component _buildErrorState(String error) {
    return div(
      classes: 'text-center py-12 bg-white rounded-lg shadow',
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
        button(
          type: ButtonType.button,
          classes:
              'px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700',
          events: {'click': (_) => _loadPackages()},
          [Component.text('Try again')],
        ),
      ],
    );
  }

  Component _buildPackageList(PackageListResponse response) {
    if (response.packages.isEmpty) {
      return div(
        classes: 'text-center py-12 bg-white rounded-lg shadow',
        [
          div(
            classes: 'inline-block p-4 bg-gray-100 rounded-full mb-4',
            [
              span(classes: 'text-gray-400 text-4xl', [RawText('&#x1F4E6;')]),
            ],
          ),
          h2(
            classes: 'text-xl font-semibold text-gray-900 mb-2',
            [Component.text('No cached packages')],
          ),
          p(
            classes: 'text-gray-600',
            [
              Component.text(
                  'Packages from pub.dev will appear here when downloaded through this registry.')
            ],
          ),
        ],
      );
    }

    return div(
      classes: 'bg-white rounded-lg shadow overflow-hidden',
      [
        // Header
        div(
          classes: 'px-6 py-4 border-b border-gray-200 bg-purple-50',
          [
            div(
              classes: 'flex justify-between items-center',
              [
                div([
                  span(
                    classes: 'text-sm text-purple-700 font-medium',
                    [
                      Component.text(
                          '${response.total} cached package${response.total != 1 ? "s" : ""}')
                    ],
                  ),
                  p(
                    classes: 'text-xs text-purple-600 mt-1',
                    [Component.text('These packages are cached from pub.dev')],
                  ),
                ]),
              ],
            ),
          ],
        ),
        // Package list
        div([
          for (final pkg in response.packages) _buildPackageRow(pkg),
        ]),
        // Pagination
        if (response.totalPages > 1) _buildPagination(response),
      ],
    );
  }

  Component _buildPackageRow(PackageInfo pkg) {
    final latest = pkg.latest;
    return div(
      classes:
          'px-6 py-4 border-b border-gray-100 last:border-0 hover:bg-gray-50',
      [
        div(
          classes: 'flex items-center justify-between',
          [
            // Package info
            div([
              div(
                classes: 'flex items-center space-x-2',
                [
                  a(
                    href: '/packages/${pkg.package.name}',
                    classes: 'font-medium text-blue-600 hover:text-blue-800',
                    [Component.text(pkg.package.name)],
                  ),
                  span(
                    classes:
                        'px-2 py-0.5 text-xs bg-purple-100 text-purple-700 rounded',
                    [Component.text('Cached')],
                  ),
                ],
              ),
              div(
                classes: 'text-sm text-gray-500 mt-1',
                [
                  Component.text(
                      'v${latest?.version ?? "?"} - ${pkg.versions.length} version${pkg.versions.length != 1 ? "s" : ""}'),
                ],
              ),
            ]),
            // Actions
            div(
              classes: 'flex items-center space-x-2',
              [
                a(
                  href: 'https://pub.dev/packages/${pkg.package.name}',
                  classes:
                      'px-3 py-1.5 text-sm text-gray-600 bg-gray-50 border border-gray-200 rounded hover:bg-gray-100 transition-colors',
                  attributes: {'target': '_blank'},
                  [Component.text('View on pub.dev')],
                ),
                button(
                  type: ButtonType.button,
                  classes:
                      'px-3 py-1.5 text-sm text-red-700 bg-red-50 border border-red-200 rounded hover:bg-red-100 transition-colors',
                  events: {'click': (_) => _deletePackage(pkg.package.name)},
                  [Component.text('Delete')],
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildPagination(PackageListResponse response) {
    return div(
      classes:
          'px-6 py-4 border-t border-gray-200 flex justify-center items-center space-x-2',
      [
        if (response.hasPrevPage)
          button(
            type: ButtonType.button,
            classes:
                'px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50',
            events: {'click': (_) => _loadPackages(page: response.page - 1)},
            [Component.text('Previous')],
          ),
        span(
          classes: 'px-4 py-2 text-gray-600',
          [Component.text('Page ${response.page} of ${response.totalPages}')],
        ),
        if (response.hasNextPage)
          button(
            type: ButtonType.button,
            classes:
                'px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50',
            events: {'click': (_) => _loadPackages(page: response.page + 1)},
            [Component.text('Next')],
          ),
      ],
    );
  }
}
