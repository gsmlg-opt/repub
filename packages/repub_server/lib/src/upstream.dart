import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Client for fetching packages from upstream pub server (e.g., pub.dev).
class UpstreamClient {
  final String baseUrl;
  final http.Client _client;

  UpstreamClient({required this.baseUrl}) : _client = http.Client();

  /// Fetch package info from upstream.
  /// Returns null if package not found.
  Future<UpstreamPackageInfo?> getPackage(String name) async {
    final url = '$baseUrl/api/packages/$name';
    try {
      final response = await _client.get(Uri.parse(url));

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        print('Upstream error fetching $name: ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return UpstreamPackageInfo.fromJson(json);
    } catch (e) {
      print('Upstream error fetching $name: $e');
      return null;
    }
  }

  /// Fetch a specific version info from upstream.
  /// Returns null if version not found.
  Future<UpstreamVersionInfo?> getVersion(String name, String version) async {
    final url = '$baseUrl/api/packages/$name/versions/$version';
    try {
      final response = await _client.get(Uri.parse(url));

      if (response.statusCode == 404) {
        return null;
      }

      if (response.statusCode != 200) {
        print('Upstream error fetching $name@$version: ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return UpstreamVersionInfo.fromJson(name, json);
    } catch (e) {
      print('Upstream error fetching $name@$version: $e');
      return null;
    }
  }

  /// Search for packages on upstream.
  /// Returns list of package names that match the query.
  /// pub.dev search API returns simple list of package names, not full package info.
  Future<List<String>> searchPackages(String query, {int page = 1}) async {
    final url = '$baseUrl/api/search?q=${Uri.encodeComponent(query)}&page=$page';
    try {
      final response = await _client.get(Uri.parse(url));

      if (response.statusCode == 404) {
        return [];
      }

      if (response.statusCode != 200) {
        print('Upstream error searching "$query": ${response.statusCode}');
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final packages = (json['packages'] as List<dynamic>?)
              ?.map((p) => (p as Map<String, dynamic>)['package'] as String)
              .toList() ??
          [];

      return packages;
    } catch (e) {
      print('Upstream error searching "$query": $e');
      return [];
    }
  }

  /// Download package archive from upstream.
  /// Returns null if download fails.
  Future<Uint8List?> downloadArchive(String archiveUrl) async {
    try {
      final response = await _client.get(Uri.parse(archiveUrl));

      if (response.statusCode != 200) {
        print('Upstream error downloading archive: ${response.statusCode}');
        return null;
      }

      return response.bodyBytes;
    } catch (e) {
      print('Upstream error downloading archive: $e');
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
        .map((v) => UpstreamVersionInfo.fromJson(name, v as Map<String, dynamic>))
        .toList();

    UpstreamVersionInfo? latest;
    if (json['latest'] != null) {
      latest = UpstreamVersionInfo.fromJson(name, json['latest'] as Map<String, dynamic>);
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

  factory UpstreamVersionInfo.fromJson(String packageName, Map<String, dynamic> json) {
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
