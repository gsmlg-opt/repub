import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

/// Main layout wrapper with header and footer
class Layout extends StatelessComponent {
  final List<Component> children;

  const Layout({required this.children, super.key});

  @override
  Component build(BuildContext context) {
    // The Document and head elements are defined in web/index.html
    // This layout just provides the page structure
    return div(
      classes: 'min-h-screen bg-gray-50 flex flex-col',
      [
        // Header
        _buildHeader(),
        // Main content
        main_(
          classes: 'flex-1 container mx-auto px-4 py-8 max-w-6xl',
          children,
        ),
        // Footer
        _buildFooter(),
      ],
    );
  }

  Component _buildHeader() {
    return header(
      classes: 'bg-white shadow-sm border-b border-gray-200',
      [
        div(
          classes: 'container mx-auto px-4 py-4 max-w-6xl',
          [
            div(
              classes: 'flex items-center justify-between',
              [
                // Logo
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
                    span(
                      classes: 'text-xl font-bold text-gray-900',
                      [Component.text('Repub')],
                    ),
                  ],
                ),
                // Navigation
                nav(
                  classes: 'flex items-center space-x-6',
                  [
                    a(
                      href: '/',
                      classes: 'text-gray-600 hover:text-gray-900 font-medium',
                      [Component.text('Packages')],
                    ),
                    a(
                      href: '/search',
                      classes: 'text-gray-600 hover:text-gray-900 font-medium',
                      [Component.text('Search')],
                    ),
                    a(
                      href: '/docs',
                      classes: 'text-gray-600 hover:text-gray-900 font-medium',
                      [Component.text('Docs')],
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

  Component _buildFooter() {
    return footer(
      classes: 'bg-white border-t border-gray-200 mt-auto',
      [
        div(
          classes: 'container mx-auto px-4 py-6 max-w-6xl',
          [
            div(
              classes: 'flex items-center justify-between text-sm text-gray-500',
              [
                span([Component.text('Repub - Private Dart Package Registry')]),
                span([Component.text('Powered by Jaspr')]),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
