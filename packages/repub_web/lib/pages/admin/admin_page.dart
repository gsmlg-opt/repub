import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:web/web.dart' as web;

import '../../src/components/admin_layout.dart';
import '../../src/services/admin_api_client.dart';

/// Admin page with login form and dashboard.
@client
class AdminPage extends StatefulComponent {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  static const _tokenKey = 'repub_admin_token';

  String? _token;
  bool _loading = true;
  String? _error;
  AdminStats? _stats;
  String _tokenInput = '';

  @override
  void initState() {
    super.initState();
    _checkStoredToken();
  }

  Future<void> _checkStoredToken() async {
    final stored = web.window.localStorage.getItem(_tokenKey);
    if (stored != null && stored.isNotEmpty) {
      final client = AdminApiClient(token: stored);
      try {
        final valid = await client.validateToken();
        if (valid) {
          setState(() {
            _token = stored;
          });
          await _loadStats();
          return;
        }
      } catch (_) {
        // Token invalid, clear it
        web.window.localStorage.removeItem(_tokenKey);
      } finally {
        client.dispose();
      }
    }
    setState(() {
      _loading = false;
    });
  }

  Future<void> _login() async {
    if (_tokenInput.isEmpty) {
      setState(() {
        _error = 'Please enter an admin token';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final client = AdminApiClient(token: _tokenInput);
    try {
      final valid = await client.validateToken();
      if (valid) {
        web.window.localStorage.setItem(_tokenKey, _tokenInput);
        setState(() {
          _token = _tokenInput;
        });
        await _loadStats();
      } else {
        setState(() {
          _error = 'Invalid admin token';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e is AdminApiException ? e.message : 'Failed to validate token';
        _loading = false;
      });
    } finally {
      client.dispose();
    }
  }

  Future<void> _loadStats() async {
    if (_token == null) return;

    final client = AdminApiClient(token: _token!);
    try {
      final stats = await client.getStats();
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e is AdminApiException ? e.message : 'Failed to load stats';
        _loading = false;
      });
    } finally {
      client.dispose();
    }
  }

  void _logout() {
    web.window.localStorage.removeItem(_tokenKey);
    setState(() {
      _token = null;
      _stats = null;
      _tokenInput = '';
    });
  }

  @override
  Component build(BuildContext context) {
    if (_token == null) {
      return _buildLoginPage();
    }

    return AdminLayout(
      currentPath: '/admin',
      onLogout: _logout,
      children: [
        if (_loading)
          _buildLoadingState()
        else if (_error != null)
          _buildErrorState(_error!)
        else if (_stats != null)
          _buildDashboard(_stats!),
      ],
    );
  }

  Component _buildLoginPage() {
    return div(
      classes: 'min-h-screen bg-gray-100 flex items-center justify-center',
      [
        div(
          classes: 'bg-white rounded-lg shadow-lg p-8 w-full max-w-md',
          [
            // Header
            div(
              classes: 'text-center mb-8',
              [
                div(
                  classes: 'w-16 h-16 bg-blue-600 rounded-xl mx-auto mb-4 flex items-center justify-center',
                  [
                    span(
                      classes: 'text-white font-bold text-2xl',
                      [Component.text('R')],
                    ),
                  ],
                ),
                h1(
                  classes: 'text-2xl font-bold text-gray-900',
                  [Component.text('Admin Login')],
                ),
                p(
                  classes: 'text-gray-600 mt-2',
                  [Component.text('Enter your admin token to continue')],
                ),
              ],
            ),
            // Error message
            if (_error != null)
              div(
                classes: 'mb-4 p-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm',
                [Component.text(_error!)],
              ),
            // Form
            div([
              div(
                classes: 'mb-4',
                [
                  label(
                    classes: 'block text-sm font-medium text-gray-700 mb-2',
                    attributes: {'for': 'token'},
                    [Component.text('Admin Token')],
                  ),
                  input(
                    id: 'token',
                    type: InputType.password,
                    classes: 'w-full px-4 py-3 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none',
                    attributes: {'placeholder': 'Enter your admin token'},
                    events: {
                      'input': (e) {
                        _tokenInput = (e.target as web.HTMLInputElement).value;
                      },
                      'keypress': (e) {
                        if ((e as web.KeyboardEvent).key == 'Enter') {
                          _login();
                        }
                      },
                    },
                  ),
                ],
              ),
              button(
                type: ButtonType.button,
                classes: _loading
                    ? 'w-full px-4 py-3 bg-gray-400 text-white font-medium rounded-lg cursor-not-allowed'
                    : 'w-full px-4 py-3 bg-blue-600 text-white font-medium rounded-lg hover:bg-blue-700 transition-colors',
                events: {'click': (_) => _login()},
                [Component.text(_loading ? 'Validating...' : 'Login')],
              ),
            ]),
            // Help text
            div(
              classes: 'mt-6 text-center text-sm text-gray-500',
              [
                p([Component.text('Create an admin token with:')]),
                code(
                  classes: 'block mt-2 p-2 bg-gray-100 rounded text-xs font-mono',
                  [Component.text('dart run repub_cli token create my-admin admin')],
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
      classes: 'grid gap-6 md:grid-cols-2 lg:grid-cols-4',
      [
        for (var i = 0; i < 4; i++)
          div(
            classes: 'bg-white rounded-lg shadow p-6 animate-pulse',
            [
              div(classes: 'h-4 bg-gray-200 rounded w-1/2 mb-3', []),
              div(classes: 'h-8 bg-gray-200 rounded w-1/3', []),
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
          [Component.text('Failed to load dashboard')],
        ),
        p(
          classes: 'text-gray-600 mb-4',
          [Component.text(error)],
        ),
        button(
          type: ButtonType.button,
          classes: 'px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700',
          events: {'click': (_) => _loadStats()},
          [Component.text('Try again')],
        ),
      ],
    );
  }

  Component _buildDashboard(AdminStats stats) {
    return Component.fragment([
      // Stats cards
      div(
        classes: 'grid gap-6 md:grid-cols-2 lg:grid-cols-4 mb-8',
        [
          _statCard('Total Packages', stats.totalPackages.toString(), 'bg-blue-500'),
          _statCard('Local Packages', stats.localPackages.toString(), 'bg-green-500'),
          _statCard('Cached Packages', stats.cachedPackages.toString(), 'bg-purple-500'),
          _statCard('Total Versions', stats.totalVersions.toString(), 'bg-orange-500'),
        ],
      ),
      // Quick actions
      div(
        classes: 'bg-white rounded-lg shadow p-6',
        [
          h2(
            classes: 'text-lg font-semibold text-gray-900 mb-4',
            [Component.text('Quick Actions')],
          ),
          div(
            classes: 'grid gap-4 md:grid-cols-2 lg:grid-cols-3',
            [
              _actionCard(
                'Manage Local Packages',
                'View and manage locally published packages',
                '/admin/packages/local',
                'bg-green-50 border-green-200 hover:bg-green-100',
              ),
              _actionCard(
                'Manage Cached Packages',
                'View and clear upstream cache',
                '/admin/packages/cached',
                'bg-purple-50 border-purple-200 hover:bg-purple-100',
              ),
              _actionCard(
                'View Registry',
                'Go to the main package registry',
                '/',
                'bg-blue-50 border-blue-200 hover:bg-blue-100',
              ),
            ],
          ),
        ],
      ),
    ]);
  }

  Component _statCard(String label, String value, String colorClass) {
    return div(
      classes: 'bg-white rounded-lg shadow overflow-hidden',
      [
        div(
          classes: 'p-6',
          [
            p(
              classes: 'text-sm font-medium text-gray-500',
              [Component.text(label)],
            ),
            p(
              classes: 'text-3xl font-bold text-gray-900 mt-2',
              [Component.text(value)],
            ),
          ],
        ),
        div(classes: '$colorClass h-1', []),
      ],
    );
  }

  Component _actionCard(String title, String description, String href, String colorClasses) {
    return a(
      href: href,
      classes: 'block p-4 border rounded-lg transition-colors $colorClasses',
      [
        h3(
          classes: 'font-medium text-gray-900',
          [Component.text(title)],
        ),
        p(
          classes: 'text-sm text-gray-600 mt-1',
          [Component.text(description)],
        ),
      ],
    );
  }
}
