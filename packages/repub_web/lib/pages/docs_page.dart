import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';

import '../src/components/layout.dart';

/// Documentation page with setup instructions
class DocsPage extends StatelessComponent {
  const DocsPage({super.key});

  @override
  Component build(BuildContext context) {
    return Layout(
      children: [
        // Header
        div(
          classes: 'mb-8',
          [
            h1(
              classes: 'text-3xl font-bold text-gray-900 mb-4',
              [Component.text('Documentation')],
            ),
            p(
              classes: 'text-lg text-gray-600',
              [
                Component.text(
                    'Learn how to configure Dart and Flutter to use this package registry.')
              ],
            ),
          ],
        ),

        // Table of Contents
        div(
          classes: 'bg-blue-50 rounded-lg p-6 mb-8',
          [
            h2(
              classes: 'text-lg font-semibold text-gray-900 mb-3',
              [Component.text('On this page')],
            ),
            ul(
              classes: 'space-y-2 text-sm',
              [
                li([
                  a(
                    href: '/docs#configure-dart',
                    classes: 'text-blue-600 hover:text-blue-800',
                    [Component.text('Configure Dart/Flutter')],
                  ),
                ]),
                li([
                  a(
                    href: '/docs#publish',
                    classes: 'text-blue-600 hover:text-blue-800',
                    [Component.text('Publishing Packages')],
                  ),
                ]),
                li([
                  a(
                    href: '/docs#authentication',
                    classes: 'text-blue-600 hover:text-blue-800',
                    [Component.text('Authentication')],
                  ),
                ]),
              ],
            ),
          ],
        ),

        // Configure Dart/Flutter Section
        _buildSection(
          id: 'configure-dart',
          title: 'Configure Dart/Flutter',
          children: [
            p(
              classes: 'text-gray-700 mb-4',
              [
                Component.text(
                    'To use this registry, you need to configure Dart to use the hosted repository URL.')
              ],
            ),

            // Method 1: PUB_HOSTED_URL
            h3(
              classes: 'text-lg font-semibold text-gray-900 mb-3 mt-6',
              [Component.text('Method 1: Environment Variable (Recommended)')],
            ),
            p(
              classes: 'text-gray-700 mb-3',
              [
                Component.text(
                    'Set the PUB_HOSTED_URL environment variable to point to this registry:')
              ],
            ),
            _buildCodeBlock('''# Linux/macOS - Add to ~/.bashrc or ~/.zshrc
export PUB_HOSTED_URL="http://localhost:8080"

# Windows - Set in System Environment Variables or run:
setx PUB_HOSTED_URL "http://localhost:8080"'''),
            p(
              classes: 'text-gray-700 mb-4',
              [
                Component.text(
                    'After setting the variable, restart your terminal and run:')
              ],
            ),
            _buildCodeBlock('''dart pub get
# or
flutter pub get'''),

            // Method 2: pubspec.yaml
            h3(
              classes: 'text-lg font-semibold text-gray-900 mb-3 mt-6',
              [Component.text('Method 2: Per-Package Configuration')],
            ),
            p(
              classes: 'text-gray-700 mb-3',
              [
                Component.text(
                    'Specify the hosted URL for specific dependencies in your pubspec.yaml:')
              ],
            ),
            _buildCodeBlock('''dependencies:
  my_package:
    version: ^1.0.0
    hosted:
      url: http://localhost:8080
      name: my_package'''),

            // Method 3: Global config
            h3(
              classes: 'text-lg font-semibold text-gray-900 mb-3 mt-6',
              [Component.text('Method 3: Global Pub Configuration')],
            ),
            p(
              classes: 'text-gray-700 mb-3',
              [Component.text('Create or edit the pub configuration file:')],
            ),
            _buildCodeBlock('''# Location: ~/.pub-cache/pub-tokens.json
{
  "hosted": [
    {
      "url": "http://localhost:8080"
    }
  ]
}'''),
          ],
        ),

        // Publishing Section
        _buildSection(
          id: 'publish',
          title: 'Publishing Packages',
          children: [
            p(
              classes: 'text-gray-700 mb-4',
              [Component.text('To publish a package to this registry:')],
            ),
            h3(
              classes: 'text-lg font-semibold text-gray-900 mb-3',
              [Component.text('1. Prepare Your Package')],
            ),
            p(
              classes: 'text-gray-700 mb-3',
              [
                Component.text(
                    'Ensure your package has a valid pubspec.yaml with proper metadata:')
              ],
            ),
            _buildCodeBlock('''name: my_package
version: 1.0.0
description: A brief description of your package
homepage: https://github.com/username/my_package

environment:
  sdk: ^3.0.0'''),
            h3(
              classes: 'text-lg font-semibold text-gray-900 mb-3 mt-6',
              [Component.text('2. Set Registry URL')],
            ),
            p(
              classes: 'text-gray-700 mb-3',
              [
                Component.text('Use the --server flag to specify the registry:')
              ],
            ),
            _buildCodeBlock(
                '''dart pub publish --server http://localhost:8080'''),
            h3(
              classes: 'text-lg font-semibold text-gray-900 mb-3 mt-6',
              [Component.text('3. Authenticate (if required)')],
            ),
            p(
              classes: 'text-gray-700 mb-3',
              [
                Component.text(
                    'If authentication is required, you\'ll be prompted to provide a token during publish.')
              ],
            ),
          ],
        ),

        // Authentication Section
        _buildSection(
          id: 'authentication',
          title: 'Authentication',
          children: [
            p(
              classes: 'text-gray-700 mb-4',
              [
                Component.text(
                    'This registry may require authentication for publishing or downloading packages.')
              ],
            ),
            h3(
              classes: 'text-lg font-semibold text-gray-900 mb-3',
              [Component.text('Using Authentication Tokens')],
            ),
            p(
              classes: 'text-gray-700 mb-3',
              [
                Component.text(
                    'Contact your registry administrator to obtain an authentication token. Store it in your pub credentials:')
              ],
            ),
            _buildCodeBlock('''# Location: ~/.pub-cache/credentials.json
{
  "accessToken": "your-token-here",
  "refreshToken": null,
  "tokenEndpoint": "http://localhost:8080/api/token",
  "scopes": ["openid"],
  "expiration": null
}'''),
            h3(
              classes: 'text-lg font-semibold text-gray-900 mb-3 mt-6',
              [Component.text('Token Scopes')],
            ),
            ul(
              classes: 'list-disc list-inside text-gray-700 space-y-2 mb-4',
              [
                li([
                  Component.text('admin - Full access including admin panel')
                ]),
                li([Component.text('publish:all - Publish any package')]),
                li([
                  Component.text(
                      'publish:pkg:<name> - Publish specific package only')
                ]),
                li([
                  Component.text(
                      'read:all - Read/download (when download auth required)')
                ]),
              ],
            ),
          ],
        ),

        // Additional Resources
        div(
          classes: 'bg-gray-100 rounded-lg p-6 mt-8',
          [
            h2(
              classes: 'text-xl font-semibold text-gray-900 mb-4',
              [Component.text('Additional Resources')],
            ),
            ul(
              classes: 'space-y-3 text-gray-700',
              [
                li([
                  span(
                      classes: 'font-medium',
                      [Component.text('Dart Pub Documentation: ')]),
                  a(
                    href: 'https://dart.dev/tools/pub/cmd',
                    classes: 'text-blue-600 hover:text-blue-800',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('dart.dev/tools/pub/cmd')],
                  ),
                ]),
                li([
                  span(
                      classes: 'font-medium',
                      [Component.text('Flutter Packages: ')]),
                  a(
                    href:
                        'https://docs.flutter.dev/packages-and-plugins/developing-packages',
                    classes: 'text-blue-600 hover:text-blue-800',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('docs.flutter.dev/packages-and-plugins')],
                  ),
                ]),
                li([
                  span(
                      classes: 'font-medium',
                      [Component.text('Repository Spec: ')]),
                  a(
                    href:
                        'https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md',
                    classes: 'text-blue-600 hover:text-blue-800',
                    attributes: {'target': '_blank', 'rel': 'noopener'},
                    [Component.text('Hosted Pub Repository Specification v2')],
                  ),
                ]),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Component _buildSection(
      {required String id,
      required String title,
      required List<Component> children}) {
    return section(
      id: id,
      classes: 'mb-12 scroll-mt-20',
      [
        h2(
          classes:
              'text-2xl font-bold text-gray-900 mb-6 pb-3 border-b-2 border-gray-200',
          [Component.text(title)],
        ),
        ...children,
      ],
    );
  }

  Component _buildCodeBlock(String code) {
    return pre(
      classes:
          'bg-gray-900 text-gray-100 rounded-lg p-4 overflow-x-auto text-sm font-mono mb-4',
      [
        Component.element(tag: 'code', children: [Component.text(code)])
      ],
    );
  }
}
