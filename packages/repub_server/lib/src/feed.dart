import 'package:repub_model/repub_model.dart';

/// RSS/Atom feed generator for package updates.
class FeedGenerator {
  final String baseUrl;
  final String title;
  final String description;

  FeedGenerator({
    required this.baseUrl,
    this.title = 'Package Updates',
    this.description = 'Recent package updates and releases',
  });

  /// Generate an RSS 2.0 feed from packages.
  String generateRss(List<PackageInfo> packages, {int limit = 20}) {
    final items = _getRecentVersions(packages, limit);
    final lastBuildDate = items.isNotEmpty
        ? _formatRssDate(items.first.publishedAt)
        : _formatRssDate(DateTime.now());

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
        '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">');
    buffer.writeln('  <channel>');
    buffer.writeln('    <title>${_escapeXml(title)}</title>');
    buffer.writeln('    <link>$baseUrl</link>');
    buffer.writeln('    <description>${_escapeXml(description)}</description>');
    buffer.writeln('    <lastBuildDate>$lastBuildDate</lastBuildDate>');
    buffer.writeln(
        '    <atom:link href="$baseUrl/feed.rss" rel="self" type="application/rss+xml"/>');

    for (final item in items) {
      buffer.writeln('    <item>');
      buffer.writeln(
          '      <title>${_escapeXml(item.packageName)} ${item.version}</title>');
      buffer
          .writeln('      <link>$baseUrl/packages/${item.packageName}</link>');
      buffer.writeln(
          '      <guid isPermaLink="false">${item.packageName}-${item.version}</guid>');
      buffer.writeln(
          '      <pubDate>${_formatRssDate(item.publishedAt)}</pubDate>');

      final desc = _getVersionDescription(item);
      buffer.writeln('      <description>${_escapeXml(desc)}</description>');
      buffer.writeln('    </item>');
    }

    buffer.writeln('  </channel>');
    buffer.writeln('</rss>');

    return buffer.toString();
  }

  /// Generate an Atom 1.0 feed from packages.
  String generateAtom(List<PackageInfo> packages, {int limit = 20}) {
    final items = _getRecentVersions(packages, limit);
    final updated = items.isNotEmpty
        ? _formatAtomDate(items.first.publishedAt)
        : _formatAtomDate(DateTime.now());

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<feed xmlns="http://www.w3.org/2005/Atom">');
    buffer.writeln('  <title>${_escapeXml(title)}</title>');
    buffer.writeln('  <subtitle>${_escapeXml(description)}</subtitle>');
    buffer.writeln('  <link href="$baseUrl" rel="alternate"/>');
    buffer.writeln('  <link href="$baseUrl/feed.atom" rel="self"/>');
    buffer.writeln('  <id>$baseUrl/</id>');
    buffer.writeln('  <updated>$updated</updated>');

    for (final item in items) {
      final itemId =
          '$baseUrl/packages/${item.packageName}/versions/${item.version}';
      buffer.writeln('  <entry>');
      buffer.writeln(
          '    <title>${_escapeXml(item.packageName)} ${item.version}</title>');
      buffer
          .writeln('    <link href="$baseUrl/packages/${item.packageName}"/>');
      buffer.writeln('    <id>$itemId</id>');
      buffer.writeln(
          '    <updated>${_formatAtomDate(item.publishedAt)}</updated>');
      buffer.writeln(
          '    <published>${_formatAtomDate(item.publishedAt)}</published>');

      final desc = _getVersionDescription(item);
      buffer.writeln('    <summary type="text">${_escapeXml(desc)}</summary>');

      final content = _getVersionContent(item);
      buffer
          .writeln('    <content type="html">${_escapeXml(content)}</content>');
      buffer.writeln('  </entry>');
    }

    buffer.writeln('</feed>');

    return buffer.toString();
  }

  /// Generate an RSS feed for a specific package.
  String generatePackageRss(PackageInfo package) {
    final buffer = StringBuffer();
    final lastBuildDate = package.versions.isNotEmpty
        ? _formatRssDate(package.versions.first.publishedAt)
        : _formatRssDate(DateTime.now());

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln(
        '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">');
    buffer.writeln('  <channel>');
    buffer.writeln(
        '    <title>${_escapeXml(package.package.name)} - Package Updates</title>');
    buffer
        .writeln('    <link>$baseUrl/packages/${package.package.name}</link>');

    final desc = _getPackageDescription(package);
    buffer.writeln('    <description>${_escapeXml(desc)}</description>');
    buffer.writeln('    <lastBuildDate>$lastBuildDate</lastBuildDate>');
    buffer.writeln(
        '    <atom:link href="$baseUrl/packages/${package.package.name}/feed.rss" rel="self" type="application/rss+xml"/>');

    // Sort versions by published date descending
    final sortedVersions = List<PackageVersion>.from(package.versions)
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    for (final version in sortedVersions.take(20)) {
      buffer.writeln('    <item>');
      buffer.writeln(
          '      <title>${_escapeXml(package.package.name)} ${version.version}</title>');
      buffer.writeln(
          '      <link>$baseUrl/packages/${package.package.name}</link>');
      buffer.writeln(
          '      <guid isPermaLink="false">${package.package.name}-${version.version}</guid>');
      buffer.writeln(
          '      <pubDate>${_formatRssDate(version.publishedAt)}</pubDate>');

      final versionDesc = _getVersionDescription(version);
      buffer.writeln(
          '      <description>${_escapeXml(versionDesc)}</description>');
      buffer.writeln('    </item>');
    }

    buffer.writeln('  </channel>');
    buffer.writeln('</rss>');

    return buffer.toString();
  }

  /// Generate an Atom feed for a specific package.
  String generatePackageAtom(PackageInfo package) {
    final buffer = StringBuffer();
    final updated = package.versions.isNotEmpty
        ? _formatAtomDate(package.versions.first.publishedAt)
        : _formatAtomDate(DateTime.now());

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<feed xmlns="http://www.w3.org/2005/Atom">');
    buffer.writeln(
        '  <title>${_escapeXml(package.package.name)} - Package Updates</title>');

    final desc = _getPackageDescription(package);
    buffer.writeln('  <subtitle>${_escapeXml(desc)}</subtitle>');
    buffer.writeln(
        '  <link href="$baseUrl/packages/${package.package.name}" rel="alternate"/>');
    buffer.writeln(
        '  <link href="$baseUrl/packages/${package.package.name}/feed.atom" rel="self"/>');
    buffer.writeln('  <id>$baseUrl/packages/${package.package.name}</id>');
    buffer.writeln('  <updated>$updated</updated>');

    // Sort versions by published date descending
    final sortedVersions = List<PackageVersion>.from(package.versions)
      ..sort((a, b) => b.publishedAt.compareTo(a.publishedAt));

    for (final version in sortedVersions.take(20)) {
      final itemId =
          '$baseUrl/packages/${package.package.name}/versions/${version.version}';
      buffer.writeln('  <entry>');
      buffer.writeln(
          '    <title>${_escapeXml(package.package.name)} ${version.version}</title>');
      buffer.writeln(
          '    <link href="$baseUrl/packages/${package.package.name}"/>');
      buffer.writeln('    <id>$itemId</id>');
      buffer.writeln(
          '    <updated>${_formatAtomDate(version.publishedAt)}</updated>');
      buffer.writeln(
          '    <published>${_formatAtomDate(version.publishedAt)}</published>');

      final versionDesc = _getVersionDescription(version);
      buffer.writeln(
          '    <summary type="text">${_escapeXml(versionDesc)}</summary>');

      final content = _getVersionContent(version);
      buffer
          .writeln('    <content type="html">${_escapeXml(content)}</content>');
      buffer.writeln('  </entry>');
    }

    buffer.writeln('</feed>');

    return buffer.toString();
  }

  /// Get recent versions sorted by publish date.
  List<PackageVersion> _getRecentVersions(
      List<PackageInfo> packages, int limit) {
    final allVersions = <PackageVersion>[];

    for (final pkg in packages) {
      // Only include hosted packages, not cached
      if (pkg.package.isUpstreamCache) continue;
      allVersions.addAll(pkg.versions);
    }

    allVersions.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
    return allVersions.take(limit).toList();
  }

  /// Format date for RSS (RFC 822).
  String _formatRssDate(DateTime date) {
    final utc = date.toUtc();
    final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];

    final day = days[utc.weekday - 1];
    final month = months[utc.month - 1];

    return '$day, ${utc.day.toString().padLeft(2, '0')} $month ${utc.year} '
        '${utc.hour.toString().padLeft(2, '0')}:'
        '${utc.minute.toString().padLeft(2, '0')}:'
        '${utc.second.toString().padLeft(2, '0')} +0000';
  }

  /// Format date for Atom (ISO 8601).
  String _formatAtomDate(DateTime date) {
    return date.toUtc().toIso8601String();
  }

  /// Escape XML special characters.
  String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Get description from version pubspec.
  String _getVersionDescription(PackageVersion version) {
    final pubspec = version.pubspec;
    final description = pubspec['description'] as String? ?? '';
    return 'Version ${version.version} of ${version.packageName}. $description'
        .trim();
  }

  /// Get HTML content for version.
  String _getVersionContent(PackageVersion version) {
    final pubspec = version.pubspec;
    final description = pubspec['description'] as String? ?? 'No description';
    final sdk = pubspec['environment']?['sdk'] as String? ?? 'Not specified';

    return '''
<p><strong>Version:</strong> ${version.version}</p>
<p><strong>Description:</strong> $description</p>
<p><strong>Dart SDK:</strong> $sdk</p>
<p><strong>Published:</strong> ${version.publishedAt.toIso8601String()}</p>
<p><a href="$baseUrl/packages/${version.packageName}">View package</a></p>
'''
        .trim();
  }

  /// Get description for a package.
  String _getPackageDescription(PackageInfo package) {
    final latest = package.latest;
    if (latest == null) return 'Updates for ${package.package.name}';

    final description = latest.pubspec['description'] as String? ?? '';
    return description.isNotEmpty
        ? description
        : 'Updates for ${package.package.name}';
  }
}
