import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

import '../../src/components/admin_layout.dart';
import '../../src/services/admin_api_client.dart';

/// Admin page with dashboard (no built-in auth).
@client
class AdminPage extends StatefulComponent {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  bool _loading = true;
  String? _error;
  AdminStats? _stats;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final client = AdminApiClient();
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

  @override
  Component build(BuildContext context) {
    return AdminLayout(
      currentPath: '/admin',
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
          classes:
              'px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700',
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
          _statCard(
              'Total Packages', stats.totalPackages.toString(), 'bg-blue-500'),
          _statCard(
              'Local Packages', stats.localPackages.toString(), 'bg-green-500'),
          _statCard('Cached Packages', stats.cachedPackages.toString(),
              'bg-purple-500'),
          _statCard('Total Versions', stats.totalVersions.toString(),
              'bg-orange-500'),
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

  Component _actionCard(
      String title, String description, String href, String colorClasses) {
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
