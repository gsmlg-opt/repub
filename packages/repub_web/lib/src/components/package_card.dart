import 'package:jaspr/jaspr.dart';
import 'package:jaspr/dom.dart';
import 'package:repub_model/repub_model_web.dart';

/// Card component for displaying package summary
class PackageCard extends StatelessComponent {
  final PackageInfo packageInfo;
  final bool isUpstream;

  const PackageCard({required this.packageInfo, this.isUpstream = false, super.key});

  @override
  Component build(BuildContext context) {
    final latest = packageInfo.latest;
    final description = latest?.pubspec['description'] as String? ?? 'No description available';
    final packageUrl = isUpstream
        ? '/upstream-packages/${packageInfo.package.name}'
        : '/packages/${packageInfo.package.name}';

    return a(
      href: packageUrl,
      classes: 'block',
      [
        div(
          classes: 'package-card bg-white rounded-lg border border-gray-200 p-6 transition-all cursor-pointer',
          [
            // Package name and version
            div(
              classes: 'flex items-start justify-between mb-3',
              [
                div([
                  h3(
                    classes: 'text-lg font-semibold text-blue-600 hover:text-blue-800',
                    [Component.text(packageInfo.package.name)],
                  ),
                  if (packageInfo.package.isDiscontinued)
                    span(
                      classes: 'inline-block mt-1 px-2 py-0.5 bg-yellow-100 text-yellow-800 text-xs rounded-full',
                      [Component.text('Discontinued')],
                    ),
                ]),
                if (latest != null)
                  span(
                    classes: 'px-3 py-1 bg-gray-100 text-gray-700 text-sm rounded-full font-mono',
                    [Component.text('v${latest.version}')],
                  ),
              ],
            ),
            // Description
            p(
              classes: 'text-gray-600 text-sm mb-4',
              [Component.text(description)],
            ),
            // Metadata
            div(
              classes: 'flex items-center space-x-4 text-xs text-gray-500',
              [
                if (latest != null)
                  span([
                    Component.text('Published ${_formatDate(latest.publishedAt)}'),
                  ]),
                span([
                  Component.text('${packageInfo.versions.length} version${packageInfo.versions.length != 1 ? "s" : ""}'),
                ]),
              ],
            ),
          ],
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'today';
    } else if (diff.inDays == 1) {
      return 'yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else if (diff.inDays < 30) {
      final weeks = (diff.inDays / 7).floor();
      return '$weeks week${weeks != 1 ? "s" : ""} ago';
    } else if (diff.inDays < 365) {
      final months = (diff.inDays / 30).floor();
      return '$months month${months != 1 ? "s" : ""} ago';
    } else {
      final years = (diff.inDays / 365).floor();
      return '$years year${years != 1 ? "s" : ""} ago';
    }
  }
}
