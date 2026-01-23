import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:repub_model/repub_model_web.dart';
import 'package:web/web.dart' as web;

import 'api_client.dart';

/// Admin statistics from the server.
class AdminStats {
  final int totalPackages;
  final int localPackages;
  final int cachedPackages;
  final int totalVersions;

  const AdminStats({
    required this.totalPackages,
    required this.localPackages,
    required this.cachedPackages,
    required this.totalVersions,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
        totalPackages: json['totalPackages'] as int,
        localPackages: json['localPackages'] as int,
        cachedPackages: json['cachedPackages'] as int,
        totalVersions: json['totalVersions'] as int,
      );
}

/// Admin API client (no built-in auth - use external auth).
class AdminApiClient {
  final String baseUrl;
  final http.Client _client;

  AdminApiClient({String? baseUrl})
      : baseUrl = baseUrl ?? _detectBaseUrl(),
        _client = http.Client();

  /// Detect API base URL based on current location.
  static String _detectBaseUrl() {
    final location = web.window.location;
    // Dev mode: web on 8081, API on 8080
    if (location.port == '8081') {
      return '${location.protocol}//${location.hostname}:8080';
    }
    // Production: same origin
    return '';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  /// Get admin statistics.
  Future<AdminStats> getStats() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/admin/stats'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch stats: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return AdminStats.fromJson(json);
  }

  /// List local packages.
  Future<PackageListResponse> listLocalPackages({int page = 1, int limit = 20}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/admin/packages/local?page=$page&limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Unauthorized',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to list local packages: ${response.body}',
      );
    }

    return _parsePackageListResponse(response.body, page, limit);
  }

  /// List cached packages.
  Future<PackageListResponse> listCachedPackages({int page = 1, int limit = 20}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/api/admin/packages/cached?page=$page&limit=$limit'),
      headers: _headers,
    );


    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to list cached packages: ${response.body}',
      );
    }

    return _parsePackageListResponse(response.body, page, limit);
  }

  /// Delete a package.
  Future<DeleteResult> deletePackage(String name) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/admin/packages/$name'),
      headers: _headers,
    );


    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Package not found: $name',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to delete package: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final success = json['success'] as Map<String, dynamic>;
    return DeleteResult(
      message: success['message'] as String,
      versionsDeleted: success['versionsDeleted'] as int? ?? 0,
    );
  }

  /// Delete a package version.
  Future<DeleteResult> deletePackageVersion(String name, String version) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/admin/packages/$name/versions/$version'),
      headers: _headers,
    );


    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Version not found: $name@$version',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to delete version: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final success = json['success'] as Map<String, dynamic>;
    return DeleteResult(message: success['message'] as String);
  }

  /// Discontinue a package.
  Future<void> discontinuePackage(String name, {String? replacedBy}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/api/admin/packages/$name/discontinue'),
      headers: _headers,
      body: replacedBy != null ? jsonEncode({'replacedBy': replacedBy}) : null,
    );


    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Package not found: $name',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to discontinue package: ${response.body}',
      );
    }
  }

  /// Clear all cached packages.
  Future<ClearCacheResult> clearCache() async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/api/admin/cache'),
      headers: _headers,
    );


    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to clear cache: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final success = json['success'] as Map<String, dynamic>;
    return ClearCacheResult(
      message: success['message'] as String,
      packagesDeleted: success['packagesDeleted'] as int? ?? 0,
      blobsDeleted: success['blobsDeleted'] as int? ?? 0,
    );
  }

  PackageListResponse _parsePackageListResponse(String body, int page, int limit) {
    final json = jsonDecode(body) as Map<String, dynamic>;
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

  PackageInfo _parsePackageInfo(Map<String, dynamic> json) {
    final package = Package(
      name: json['name'] as String,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDiscontinued: json['isDiscontinued'] as bool? ?? false,
      replacedBy: json['replacedBy'] as String?,
    );

    final versions = (json['versions'] as List<dynamic>?)
            ?.map((v) => _parsePackageVersion(json['name'] as String, v as Map<String, dynamic>))
            .toList() ??
        [];

    return PackageInfo(package: package, versions: versions);
  }

  PackageVersion _parsePackageVersion(String packageName, Map<String, dynamic> json) {
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

  void dispose() {
    _client.close();
  }
}

class AdminApiException implements Exception {
  final int statusCode;
  final String message;

  AdminApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'AdminApiException($statusCode): $message';
}

class DeleteResult {
  final String message;
  final int versionsDeleted;

  DeleteResult({required this.message, this.versionsDeleted = 0});
}

class ClearCacheResult {
  final String message;
  final int packagesDeleted;
  final int blobsDeleted;

  ClearCacheResult({
    required this.message,
    this.packagesDeleted = 0,
    this.blobsDeleted = 0,
  });
}
