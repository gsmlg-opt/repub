import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:repub_model/repub_model_web.dart';
import 'package:web/web.dart' as web;

/// API client for communicating with the Repub backend
class ApiClient {
  final String baseUrl;
  final http.Client _client;

  ApiClient({String? baseUrl})
      : baseUrl = baseUrl ?? _detectBaseUrl(),
        _client = http.Client();

  /// Detect API base URL based on current location.
  /// In dev mode (port 8081), use API server on port 8080.
  static String _detectBaseUrl() {
    final location = web.window.location;
    // Dev mode: web on 8081, API on 8080
    if (location.port == '8081') {
      return '${location.protocol}//${location.hostname}:8080';
    }
    // Production: same origin
    return '';
  }

  /// Get package info including all versions
  Future<PackageInfo?> getPackage(String name) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/packages/$name'),
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch package: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parsePackageInfo(json);
  }

  /// Get a specific package version
  Future<PackageVersion?> getPackageVersion(String name, String version) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/packages/$name/versions/$version'),
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch version: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parsePackageVersion(name, json);
  }

  /// List all packages (paginated)
  Future<PackageListResponse> listPackages(
      {int page = 1, int limit = 20}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/packages?page=$page&limit=$limit'),
    );

    if (response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to list packages: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final packages = (json['packages'] as List<dynamic>?)
            ?.map((p) => _parsePackageInfo(p as Map<String, dynamic>))
            .toList() ??
        [];

    return PackageListResponse(
      packages: packages,
      total: json['total'] as int? ?? packages.length,
      page: json['page'] as int? ?? page,
      limit: json['limit'] as int? ?? limit,
    );
  }

  /// Search packages by query (local packages only)
  Future<PackageListResponse> searchPackages(String query,
      {int page = 1, int limit = 20}) async {
    final response = await _client.get(
      Uri.parse(
          '$baseUrl/api/packages/search?q=${Uri.encodeComponent(query)}&page=$page&limit=$limit'),
    );

    if (response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to search packages: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final packages = (json['packages'] as List<dynamic>?)
            ?.map((p) => _parsePackageInfo(p as Map<String, dynamic>))
            .toList() ??
        [];

    return PackageListResponse(
      packages: packages,
      total: json['total'] as int? ?? packages.length,
      page: json['page'] as int? ?? page,
      limit: json['limit'] as int? ?? limit,
    );
  }

  /// Search packages from upstream (pub.dev)
  Future<PackageListResponse> searchPackagesUpstream(String query,
      {int page = 1, int limit = 20}) async {
    final response = await _client.get(
      Uri.parse(
          '$baseUrl/api/packages/search/upstream?q=${Uri.encodeComponent(query)}&page=$page&limit=$limit'),
    );

    if (response.statusCode == 503) {
      // Upstream disabled
      return PackageListResponse(
        packages: [],
        total: 0,
        page: page,
        limit: limit,
      );
    }

    if (response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to search upstream packages: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final packages = (json['packages'] as List<dynamic>?)
            ?.map((p) => _parsePackageInfo(p as Map<String, dynamic>))
            .toList() ??
        [];

    return PackageListResponse(
      packages: packages,
      total: json['total'] as int? ?? packages.length,
      page: json['page'] as int? ?? page,
      limit: json['limit'] as int? ?? limit,
    );
  }

  /// Get upstream package info from pub.dev
  Future<PackageInfo?> getUpstreamPackage(String name) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/upstream/packages/$name'),
    );

    if (response.statusCode == 404) {
      return null;
    }

    if (response.statusCode == 503) {
      throw ApiException(
        statusCode: 503,
        message: 'Upstream is not enabled',
      );
    }

    if (response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch upstream package: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return _parsePackageInfo(json);
  }

  PackageInfo _parsePackageInfo(Map<String, dynamic> json) {
    final package = Package(
      name: json['name'] as String,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDiscontinued: json['isDiscontinued'] as bool? ?? false,
      replacedBy: json['replacedBy'] as String?,
    );

    final versions = (json['versions'] as List<dynamic>?)
            ?.map((v) => _parsePackageVersion(
                json['name'] as String, v as Map<String, dynamic>))
            .toList() ??
        [];

    return PackageInfo(package: package, versions: versions);
  }

  PackageVersion _parsePackageVersion(
      String packageName, Map<String, dynamic> json) {
    return PackageVersion(
      packageName: packageName,
      version: json['version'] as String,
      pubspec: json['pubspec'] as Map<String, dynamic>? ?? {},
      archiveKey: json['archive_url'] as String? ?? '',
      archiveSha256: json['archive_sha256'] as String? ?? '',
      publishedAt: json['published'] != null
          ? DateTime.parse(json['published'] as String)
          : DateTime.now(),
    );
  }

  /// Get version information
  Future<Map<String, dynamic>> getVersion() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/version'),
    );

    if (response.statusCode != 200) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch version: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;

  ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class PackageListResponse {
  final List<PackageInfo> packages;
  final int total;
  final int page;
  final int limit;

  PackageListResponse({
    required this.packages,
    required this.total,
    required this.page,
    required this.limit,
  });

  int get totalPages => (total / limit).ceil();
  bool get hasNextPage => page < totalPages;
  bool get hasPrevPage => page > 1;
}
