import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Admin layout with sidebar navigation (no built-in auth).
class AdminLayout extends StatelessComponent {
  final List<Component> children;
  final String currentPath;

  const AdminLayout({
    required this.children,
    required this.currentPath,
    super.key,
  });

  @override
  Component build(BuildContext context) {
    return div(
      classes: 'min-h-screen bg-gray-100 flex',
      [
        // Sidebar
        _buildSidebar(),
        // Main content
        div(
          classes: 'flex-1 flex flex-col',
          [
            // Top header
            _buildHeader(),
            // Content area
            main_(
              classes: 'flex-1 p-6 overflow-auto',
              children,
            ),
          ],
        ),
      ],
    );
  }

  Component _buildSidebar() {
    return aside(
      classes: 'w-64 bg-gray-900 text-white flex flex-col',
      [
        // Logo area
        div(
          classes: 'p-4 border-b border-gray-700',
          [
            a(
              href: '/',
              classes: 'flex items-center space-x-3',
              [
                div(
                  classes: 'w-10 h-10 bg-blue-600 rounded-lg flex items-center justify-center',
                  [
                    span(
                      classes: 'text-white font-bold text-xl',
                      [Component.text('R')],
                    ),
                  ],
                ),
                div([
                  span(
                    classes: 'text-xl font-bold',
                    [Component.text('Repub')],
                  ),
                  span(
                    classes: 'text-xs text-gray-400 block',
                    [Component.text('Admin Panel')],
                  ),
                ]),
              ],
            ),
          ],
        ),
        // Navigation
        nav(
          classes: 'flex-1 p-4 space-y-2',
          [
            _navLink('/admin', 'Dashboard', _isActive('/admin')),
            _navLink('/admin/packages/local', 'Local Packages', _isActive('/admin/packages/local')),
            _navLink('/admin/packages/cached', 'Cached Packages', _isActive('/admin/packages/cached')),
          ],
        ),
        // Footer
        div(
          classes: 'p-4 border-t border-gray-700',
          [
            a(
              href: '/',
              classes: 'flex items-center text-gray-400 hover:text-white transition-colors',
              [
                span(classes: 'mr-2', [Component.text('<-')]),
                Component.text('Back to Registry'),
              ],
            ),
          ],
        ),
      ],
    );
  }

  bool _isActive(String path) {
    if (path == '/admin') {
      return currentPath == '/admin' || currentPath == '/admin/';
    }
    return currentPath.startsWith(path);
  }

  Component _navLink(String href, String label, bool isActive) {
    return a(
      href: href,
      classes: isActive
          ? 'block px-4 py-2 rounded-lg bg-gray-700 text-white font-medium'
          : 'block px-4 py-2 rounded-lg text-gray-300 hover:bg-gray-800 hover:text-white transition-colors',
      [Component.text(label)],
    );
  }

  Component _buildHeader() {
    return header(
      classes: 'bg-white shadow-sm border-b border-gray-200 px-6 py-4',
      [
        h1(
          classes: 'text-xl font-semibold text-gray-900',
          [Component.text(_getPageTitle())],
        ),
      ],
    );
  }

  String _getPageTitle() {
    if (currentPath == '/admin' || currentPath == '/admin/') {
      return 'Dashboard';
    }
    if (currentPath.startsWith('/admin/packages/local')) {
      return 'Local Packages';
    }
    if (currentPath.startsWith('/admin/packages/cached')) {
      return 'Cached Packages';
    }
    return 'Admin';
  }
}
