import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:repub_model/repub_model.dart' show Logger;

/// Client for fetching packages from upstream pub server (e.g., pub.dev).
class UpstreamClient {
  final String baseUrl;
  final http.Client _client;

  /// Default timeout for HTTP requests.
  static const _timeout = Duration(seconds: 10);

  /// Maximum number of packages to fetch in a batch to prevent DoS.
  static const _maxBatchSize = 100;

  UpstreamClient({required this.baseUrl}) : _client = http.Client();

  /// Fetch package info from upstream.
  /// Returns null if package not found.
  Future<UpstreamPackageInfo?> getPackage(String name) async {
    final url = '$baseUrl/api/packages/$name';
    try {
      final response = await _client.get(Uri.parse(url)).timeout(_timeout);

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        Logger.warn('Upstream error fetching package',
            component: 'upstream',
            metadata: {
              'package': name,
              'statusCode': response.statusCode,
            });
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return UpstreamPackageInfo.fromJson(json);
    } catch (e) {
      Logger.error('Upstream error fetching package',
          component: 'upstream',
          error: e,
          metadata: {
            'package': name,
          });
      return null;
    }
  }

  /// Fetch multiple packages in parallel with concurrency limit.
  ///
  /// The list of names is capped at [_maxBatchSize] to prevent DoS attacks.
  Future<List<UpstreamPackageInfo>> getPackagesBatch(
    List<String> names, {
    int concurrency = 5,
  }) async {
    // Cap batch size to prevent resource exhaustion
    final cappedNames =
        names.length > _maxBatchSize ? names.sublist(0, _maxBatchSize) : names;

    if (names.length > _maxBatchSize) {
      Logger.warn(
        'Batch size exceeded maximum, truncating',
        component: 'upstream',
        metadata: {
          'requested': names.length,
          'maxBatchSize': _maxBatchSize,
        },
      );
    }

    final results = <UpstreamPackageInfo>[];

    // Process in batches to limit concurrency
    for (var i = 0; i < cappedNames.length; i += concurrency) {
      final batch = cappedNames.skip(i).take(concurrency);
      final futures = batch.map((name) => getPackage(name));
      final batchResults = await Future.wait(futures);
      results.addAll(batchResults.whereType<UpstreamPackageInfo>());
    }

    return results;
  }

  /// Fetch a specific version info from upstream.
  /// Returns null if version not found.
  Future<UpstreamVersionInfo?> getVersion(String name, String version) async {
    final url = '$baseUrl/api/packages/$name/versions/$version';
    try {
      final response = await _client.get(Uri.parse(url)).timeout(_timeout);

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        Logger.warn('Upstream error fetching version',
            component: 'upstream',
            metadata: {
              'package': name,
              'version': version,
              'statusCode': response.statusCode,
            });
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return UpstreamVersionInfo.fromJson(name, json);
    } catch (e) {
      Logger.error('Upstream error fetching version',
          component: 'upstream',
          error: e,
          metadata: {
            'package': name,
            'version': version,
          });
      return null;
    }
  }

  /// Search for packages on upstream.
  /// Returns list of package names that match the query.
  /// pub.dev search API returns simple list of package names, not full package info.
  Future<List<String>> searchPackages(String query, {int page = 1}) async {
    final url =
        '$baseUrl/api/search?q=${Uri.encodeComponent(query)}&page=$page';
    try {
      final response = await _client.get(Uri.parse(url)).timeout(_timeout);

      if (response.statusCode == 404) {
        return [];
      }

      if (response.statusCode != 200) {
        Logger.warn('Upstream error searching',
            component: 'upstream',
            metadata: {
              'query': query,
              'statusCode': response.statusCode,
            });
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final packages = (json['packages'] as List<dynamic>?)
              ?.map((p) => (p as Map<String, dynamic>)['package'] as String)
              .toList() ??
          [];

      return packages;
    } catch (e) {
      Logger.error('Upstream error searching',
          component: 'upstream',
          error: e,
          metadata: {
            'query': query,
          });
      return [];
    }
  }

  /// Download package archive from upstream.
  /// Returns null if download fails.
  Future<Uint8List?> downloadArchive(String archiveUrl) async {
    try {
      // Use longer timeout for archive downloads
      final response = await _client.get(Uri.parse(archiveUrl)).timeout(
            const Duration(seconds: 60),
          );

      if (response.statusCode != 200) {
        Logger.warn('Upstream error downloading archive',
            component: 'upstream',
            metadata: {
              'url': archiveUrl,
              'statusCode': response.statusCode,
            });
        return null;
      }

      return response.bodyBytes;
    } catch (e) {
      Logger.error('Upstream error downloading archive',
          component: 'upstream',
          error: e,
          metadata: {
            'url': archiveUrl,
          });
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}

/// Package info from upstream.
class UpstreamPackageInfo {
  final String name;
  final UpstreamVersionInfo? latest;
  final List<UpstreamVersionInfo> versions;
  final bool isDiscontinued;
  final String? replacedBy;

  UpstreamPackageInfo({
    required this.name,
    this.latest,
    required this.versions,
    this.isDiscontinued = false,
    this.replacedBy,
  });

  factory UpstreamPackageInfo.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String;
    final versionsJson = json['versions'] as List<dynamic>? ?? [];

    final versions = versionsJson
        .map((v) =>
            UpstreamVersionInfo.fromJson(name, v as Map<String, dynamic>))
        .toList();

    UpstreamVersionInfo? latest;
    if (json['latest'] != null) {
      latest = UpstreamVersionInfo.fromJson(
          name, json['latest'] as Map<String, dynamic>);
    }

    return UpstreamPackageInfo(
      name: name,
      latest: latest,
      versions: versions,
      isDiscontinued: json['isDiscontinued'] as bool? ?? false,
      replacedBy: json['replacedBy'] as String?,
    );
  }
}

/// Version info from upstream.
class UpstreamVersionInfo {
  final String packageName;
  final String version;
  final String archiveUrl;
  final String? archiveSha256;
  final Map<String, dynamic> pubspec;
  final DateTime? published;

  UpstreamVersionInfo({
    required this.packageName,
    required this.version,
    required this.archiveUrl,
    this.archiveSha256,
    required this.pubspec,
    this.published,
  });

  factory UpstreamVersionInfo.fromJson(
      String packageName, Map<String, dynamic> json) {
    return UpstreamVersionInfo(
      packageName: packageName,
      version: json['version'] as String,
      archiveUrl: json['archive_url'] as String? ?? '',
      archiveSha256: json['archive_sha256'] as String?,
      pubspec: json['pubspec'] as Map<String, dynamic>? ?? {},
      published: json['published'] != null
          ? DateTime.tryParse(json['published'] as String)
          : null,
    );
  }
}
