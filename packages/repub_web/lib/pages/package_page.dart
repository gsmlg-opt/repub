import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:repub_model/repub_model_web.dart';

import '../src/components/layout.dart';
import '../src/services/api_client.dart';

/// Package detail page showing versions and metadata
@client
class PackagePage extends StatefulComponent {
  final String packageName;

  const PackagePage({required this.packageName, super.key});

  @override
  State<PackagePage> createState() => _PackagePageState();
}

class _PackagePageState extends State<PackagePage> {
  bool _loading = true;
  String? _error;
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackage();
  }

  Future<void> _loadPackage() async {
    final apiClient = ApiClient();
    try {
      final info = await apiClient.getPackage(component.packageName);
      setState(() {
        _packageInfo = info;
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
      return Layout(children: [_buildLoadingState()]);
    }

    if (_error != null) {
      return Layout(children: [_buildErrorState(_error!)]);
    }

    if (_packageInfo == null) {
      return Layout(children: [_buildNotFoundState()]);
    }

    return Layout(children: [_buildPackageDetail(_packageInfo!)]);
  }

  Component _buildLoadingState() {
    return div(
      classes: 'animate-pulse',
      [
        div(classes: 'h-10 bg-gray-200 rounded w-1/3 mb-4', []),
        div(classes: 'h-6 bg-gray-200 rounded w-1/2 mb-8', []),
        div(
          classes: 'grid grid-cols-3 gap-6',
          [
            div(
              classes: 'col-span-2',
              [
                div(classes: 'h-48 bg-gray-200 rounded mb-4', []),
                div(classes: 'h-32 bg-gray-200 rounded', []),
              ],
            ),
            div([
              div(classes: 'h-64 bg-gray-200 rounded', []),
            ]),
          ],
        ),
      ],
    );
  }

  Component _buildNotFoundState() {
    return div(
      classes: 'text-center py-16',
      [
        div(
          classes: 'inline-block p-4 bg-gray-100 rounded-full mb-4',
          [span(classes: 'text-4xl', [RawText('&#x1F4E6;')])],
        ),
        h2(
          classes: 'text-2xl font-semibold text-gray-900 mb-2',
          [Component.text('Package not found')],
        ),
        p(
          classes: 'text-gray-600 mb-6',
          [Component.text('The package "${component.packageName}" does not exist.')],
        ),
        a(
          href: '/',
          classes: 'inline-block px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700',
          [Component.text('Browse all packages')],
        ),
      ],
    );
  }

  Component _buildErrorState(String error) {
    return div(
      classes: 'text-center py-16',
      [
        div(
          classes: 'inline-block p-4 bg-red-50 rounded-full mb-4',
          [span(classes: 'text-red-500 text-4xl', [Component.text('!')])],
        ),
        h2(
          classes: 'text-xl font-semibold text-gray-900 mb-2',
          [Component.text('Failed to load package')],
        ),
        p(
          classes: 'text-gray-600 mb-4',
          [Component.text(error)],
        ),
        a(
          href: '/packages/${component.packageName}',
          classes: 'text-blue-600 hover:text-blue-800',
          [Component.text('Try again')],
        ),
      ],
    );
  }

  Component _buildPackageDetail(PackageInfo info) {
    final latest = info.latest;
    final pubspec = latest?.pubspec ?? {};
    final description = pubspec['description'] as String? ?? 'No description available';
    final homepage = pubspec['homepage'] as String?;
    final repository = pubspec['repository'] as String?;
    final documentation = pubspec['documentation'] as String?;

    return Component.fragment([
      // Breadcrumb
      nav(
        classes: 'mb-6',
        [
          ol(
            classes: 'flex items-center space-x-2 text-sm',
            [
              li([
                a(
                  href: '/',
                  classes: 'text-gray-500 hover:text-gray-700',
                  [Component.text('Packages')],
                ),
              ]),
              li(classes: 'text-gray-400', [Component.text('/')]),
              li(classes: 'text-gray-900 font-medium', [Component.text(component.packageName)]),
            ],
          ),
        ],
      ),

      // Header
      div(
        classes: 'mb-8',
        [
          div(
            classes: 'flex items-start justify-between',
            [
              div([
                h1(
                  classes: 'text-3xl font-bold text-gray-900 mb-2',
                  [Component.text(component.packageName)],
                ),
                if (info.package.isDiscontinued)
                  div(
                    classes: 'inline-flex items-center px-3 py-1 bg-yellow-100 text-yellow-800 text-sm rounded-full mb-2',
                    [
                      Component.text('Discontinued'),
                      if (info.package.replacedBy != null)
                        span([
                          Component.text(' - Use '),
                          a(
                            href: '/packages/${info.package.replacedBy}',
                            classes: 'underline',
                            [Component.text(info.package.replacedBy!)],
                          ),
                          Component.text(' instead'),
                        ]),
                    ],
                  ),
              ]),
              if (latest != null)
                div(
                  classes: 'text-right',
                  [
                    span(
                      classes: 'inline-block px-4 py-2 bg-blue-100 text-blue-800 rounded-lg font-mono text-lg',
                      [Component.text('v${latest.version}')],
                    ),
                  ],
                ),
            ],
          ),
          p(
            classes: 'text-lg text-gray-600 mt-4',
            [Component.text(description)],
          ),
        ],
      ),

      // Main content grid
      div(
        classes: 'grid grid-cols-1 lg:grid-cols-3 gap-8',
        [
          // Left column - Main content
          div(
            classes: 'lg:col-span-2',
            [
              // Installing section
              _buildSection(
                'Installing',
                [
                  _buildCodeBlock('''
# Add to your pubspec.yaml dependencies:
dependencies:
  ${component.packageName}: ^${latest?.version ?? '1.0.0'}

# Or run:
dart pub add ${component.packageName} --hosted-url=\${REPUB_URL}'''),
                ],
              ),

              // Versions section
              _buildSection(
                'Versions',
                [_buildVersionsTable(info.versions)],
              ),

              // Dependencies section
              if (pubspec['dependencies'] != null)
                _buildSection(
                  'Dependencies',
                  [_buildDependencies(pubspec['dependencies'] as Map<String, dynamic>)],
                ),
            ],
          ),

          // Right column - Sidebar
          div([
            // Metadata card
            div(
              classes: 'bg-white rounded-lg border border-gray-200 p-6 mb-6',
              [
                h3(
                  classes: 'font-semibold text-gray-900 mb-4',
                  [Component.text('Metadata')],
                ),
                dl(
                  classes: 'space-y-3 text-sm',
                  [
                    if (latest != null)
                      ..._buildMetadataItem('Latest', latest.version),
                    ..._buildMetadataItem('Versions', info.versions.length.toString()),
                    if (latest != null)
                      ..._buildMetadataItem('Published', _formatDate(latest.publishedAt)),
                    if (pubspec['environment'] != null)
                      ..._buildMetadataItem('SDK', _formatSdk(pubspec)),
                  ],
                ),
              ],
            ),

            // Links card
            if (homepage != null || repository != null || documentation != null)
              div(
                classes: 'bg-white rounded-lg border border-gray-200 p-6',
                [
                  h3(
                    classes: 'font-semibold text-gray-900 mb-4',
                    [Component.text('Links')],
                  ),
                  ul(
                    classes: 'space-y-2 text-sm',
                    [
                      if (homepage != null)
                        li([
                          a(
                            href: homepage,
                            classes: 'text-blue-600 hover:text-blue-800 flex items-center',
                            attributes: {'target': '_blank', 'rel': 'noopener'},
                            [Component.text('Homepage')],
                          ),
                        ]),
                      if (repository != null)
                        li([
                          a(
                            href: repository,
                            classes: 'text-blue-600 hover:text-blue-800 flex items-center',
                            attributes: {'target': '_blank', 'rel': 'noopener'},
                            [Component.text('Repository')],
                          ),
                        ]),
                      if (documentation != null)
                        li([
                          a(
                            href: documentation,
                            classes: 'text-blue-600 hover:text-blue-800 flex items-center',
                            attributes: {'target': '_blank', 'rel': 'noopener'},
                            [Component.text('Documentation')],
                          ),
                        ]),
                    ],
                  ),
                ],
              ),
          ]),
        ],
      ),
    ]);
  }

  Component _buildSection(String title, List<Component> children) {
    return section(
      classes: 'mb-8',
      [
        h2(
          classes: 'text-xl font-semibold text-gray-900 mb-4 pb-2 border-b border-gray-200',
          [Component.text(title)],
        ),
        ...children,
      ],
    );
  }

  Component _buildCodeBlock(String code) {
    return pre(
      classes: 'bg-gray-900 text-gray-100 rounded-lg p-4 overflow-x-auto text-sm font-mono',
      [Component.element(tag: 'code', children: [Component.text(code)])],
    );
  }

  Component _buildVersionsTable(List<PackageVersion> versions) {
    // Sort versions by publishedAt descending
    final sorted = [...versions]..sort((v1, v2) => v2.publishedAt.compareTo(v1.publishedAt));

    return div(
      classes: 'overflow-hidden rounded-lg border border-gray-200',
      [
        table(
          classes: 'min-w-full divide-y divide-gray-200',
          [
            thead(
              classes: 'bg-gray-50',
              [
                tr([
                  th(
                    classes: 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider',
                    [Component.text('Version')],
                  ),
                  th(
                    classes: 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider',
                    [Component.text('Published')],
                  ),
                  th(
                    classes: 'px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider',
                    [Component.text('SDK')],
                  ),
                ]),
              ],
            ),
            tbody(
              classes: 'bg-white divide-y divide-gray-200',
              [
                for (final version in sorted.take(10))
                  tr([
                    td(
                      classes: 'px-6 py-4 whitespace-nowrap',
                      [
                        span(
                          classes: 'font-mono text-blue-600',
                          [Component.text(version.version)],
                        ),
                      ],
                    ),
                    td(
                      classes: 'px-6 py-4 whitespace-nowrap text-sm text-gray-500',
                      [Component.text(_formatDate(version.publishedAt))],
                    ),
                    td(
                      classes: 'px-6 py-4 whitespace-nowrap text-sm text-gray-500',
                      [Component.text(_formatSdk(version.pubspec))],
                    ),
                  ]),
              ],
            ),
          ],
        ),
        if (versions.length > 10)
          div(
            classes: 'px-6 py-3 bg-gray-50 text-sm text-gray-500 text-center',
            [Component.text('...and ${versions.length - 10} more versions')],
          ),
      ],
    );
  }

  Component _buildDependencies(Map<String, dynamic> deps) {
    return div(
      classes: 'flex flex-wrap gap-2',
      [
        for (final entry in deps.entries)
          span(
            classes: 'inline-flex items-center px-3 py-1 bg-gray-100 text-gray-700 rounded-full text-sm',
            [
              span(classes: 'font-medium', [Component.text(entry.key)]),
              span(classes: 'mx-1 text-gray-400', [Component.text(':')]),
              span(classes: 'text-gray-500', [Component.text(entry.value.toString())]),
            ],
          ),
      ],
    );
  }

  List<Component> _buildMetadataItem(String label, String value) {
    return [
      div(
        classes: 'flex justify-between',
        [
          dt(classes: 'text-gray-500', [Component.text(label)]),
          dd(classes: 'text-gray-900 font-medium', [Component.text(value)]),
        ],
      ),
    ];
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatSdk(Map<String, dynamic> pubspec) {
    final env = pubspec['environment'] as Map<String, dynamic>?;
    if (env == null) return '-';
    return env['sdk']?.toString() ?? '-';
  }
}
