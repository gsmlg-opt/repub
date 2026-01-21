import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:repub_model/repub_model_web.dart';
import 'package:web/web.dart' as web;

import '../../src/components/admin_layout.dart';
import '../../src/services/admin_api_client.dart';
import '../../src/services/api_client.dart';

/// Admin page for managing local packages.
@client
class AdminLocalPackagesPage extends StatefulComponent {
  const AdminLocalPackagesPage({super.key});

  @override
  State<AdminLocalPackagesPage> createState() => _AdminLocalPackagesPageState();
}

class _AdminLocalPackagesPageState extends State<AdminLocalPackagesPage> {
  static const _tokenKey = 'repub_admin_token';

  String? _token;
  bool _loading = true;
  String? _error;
  PackageListResponse? _response;
  String? _actionMessage;
  bool _actionError = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  void _checkAuth() {
    final stored = web.window.localStorage.getItem(_tokenKey);
    if (stored == null || stored.isEmpty) {
      // Redirect to admin login
      web.window.location.href = '/admin';
      return;
    }
    _token = stored;
    _loadPackages();
  }

  Future<void> _loadPackages({int page = 1}) async {
    if (_token == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final client = AdminApiClient(token: _token!);
    try {
      final response = await client.listLocalPackages(page: page);
      setState(() {
        _response = response;
        _loading = false;
      });
    } catch (e) {
      if (e is AdminApiException && (e.statusCode == 401 || e.statusCode == 403)) {
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
    if (_token == null) return;

    final confirmed = web.window.confirm('Are you sure you want to delete "$name" and all its versions?');
    if (!confirmed) return;

    final client = AdminApiClient(token: _token!);
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

  Future<void> _discontinuePackage(String name) async {
    if (_token == null) return;

    final replacedBy = web.window.prompt('Replace with package (optional):');

    final client = AdminApiClient(token: _token!);
    try {
      await client.discontinuePackage(
        name,
        replacedBy: replacedBy?.isNotEmpty == true ? replacedBy : null,
      );
      setState(() {
        _actionMessage = 'Package "$name" marked as discontinued';
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

  void _logout() {
    web.window.localStorage.removeItem(_tokenKey);
    web.window.location.href = '/admin';
  }

  @override
  Component build(BuildContext context) {
    return AdminLayout(
      currentPath: '/admin/packages/local',
      onLogout: _logout,
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
                    events: {'click': (_) => setState(() => _actionMessage = null)},
                    [Component.text('x')],
                  ),
                ],
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
                classes: 'flex items-center justify-between py-4 border-b border-gray-100 last:border-0',
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
          classes: 'px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700',
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
            [Component.text('No local packages')],
          ),
          p(
            classes: 'text-gray-600',
            [Component.text('Publish your first package to get started.')],
          ),
        ],
      );
    }

    return div(
      classes: 'bg-white rounded-lg shadow overflow-hidden',
      [
        // Header
        div(
          classes: 'px-6 py-4 border-b border-gray-200 flex justify-between items-center',
          [
            span(
              classes: 'text-sm text-gray-500',
              [Component.text('${response.total} local package${response.total != 1 ? "s" : ""}')],
            ),
          ],
        ),
        // Package list
        div([
          for (final pkg in response.packages)
            _buildPackageRow(pkg),
        ]),
        // Pagination
        if (response.totalPages > 1)
          _buildPagination(response),
      ],
    );
  }

  Component _buildPackageRow(PackageInfo pkg) {
    final latest = pkg.latest;
    return div(
      classes: 'px-6 py-4 border-b border-gray-100 last:border-0 hover:bg-gray-50',
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
                  if (pkg.package.isDiscontinued)
                    span(
                      classes: 'px-2 py-0.5 text-xs bg-yellow-100 text-yellow-800 rounded',
                      [Component.text('Discontinued')],
                    ),
                ],
              ),
              div(
                classes: 'text-sm text-gray-500 mt-1',
                [
                  Component.text('v${latest?.version ?? "?"} - ${pkg.versions.length} version${pkg.versions.length != 1 ? "s" : ""}'),
                ],
              ),
            ]),
            // Actions
            div(
              classes: 'flex items-center space-x-2',
              [
                if (!pkg.package.isDiscontinued)
                  button(
                    type: ButtonType.button,
                    classes: 'px-3 py-1.5 text-sm text-yellow-700 bg-yellow-50 border border-yellow-200 rounded hover:bg-yellow-100 transition-colors',
                    events: {'click': (_) => _discontinuePackage(pkg.package.name)},
                    [Component.text('Discontinue')],
                  ),
                button(
                  type: ButtonType.button,
                  classes: 'px-3 py-1.5 text-sm text-red-700 bg-red-50 border border-red-200 rounded hover:bg-red-100 transition-colors',
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
      classes: 'px-6 py-4 border-t border-gray-200 flex justify-center items-center space-x-2',
      [
        if (response.hasPrevPage)
          button(
            type: ButtonType.button,
            classes: 'px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50',
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
            classes: 'px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50',
            events: {'click': (_) => _loadPackages(page: response.page + 1)},
            [Component.text('Next')],
          ),
      ],
    );
  }
}
