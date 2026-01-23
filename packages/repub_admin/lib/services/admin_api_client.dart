import 'dart:convert';
import 'package:web/web.dart' as web;
import 'package:http/http.dart' as http;
import 'package:repub_model/repub_model.dart';

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

class PackageListResponse {
  final List<PackageInfo> packages;
  final int total;
  final int page;
  final int limit;

  int get totalPages => (total / limit).ceil();
  bool get hasPrevPage => page > 1;
  bool get hasNextPage => page < totalPages;

  const PackageListResponse({
    required this.packages,
    required this.total,
    required this.page,
    required this.limit,
  });
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

class AdminApiException implements Exception {
  final int statusCode;
  final String message;

  AdminApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'AdminApiException($statusCode): $message';
}

class AdminApiClient {
  final String baseUrl;
  final http.Client _client;

  AdminApiClient({String? baseUrl})
      : baseUrl = baseUrl ?? _detectBaseUrl(),
        _client = http.Client();

  static String _detectBaseUrl() {
    final location = web.window.location;
    // Dev mode: admin on different port, API on 8080
    if (location.port == '8082') {
      return '${location.protocol}//${location.hostname}:8080';
    }
    // Production: same origin
    return '';
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
      };

  Future<AdminStats> getStats() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/stats'),
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

  Future<PackageListResponse> listLocalPackages({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/packages/local?page=$page&limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to list local packages: ${response.body}',
      );
    }

    return _parsePackageListResponse(response.body, page, limit);
  }

  Future<PackageListResponse> listCachedPackages({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/packages/cached?page=$page&limit=$limit'),
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

  Future<DeleteResult> deletePackage(String name) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/admin/api/packages/$name'),
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

  Future<DeleteResult> deletePackageVersion(String name, String version) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/admin/api/packages/$name/versions/$version'),
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

  Future<void> discontinuePackage(String name, {String? replacedBy}) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/api/packages/$name/discontinue'),
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

  Future<ClearCacheResult> clearCache() async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/admin/api/cache'),
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

  PackageListResponse _parsePackageListResponse(
    String body,
    int page,
    int limit,
  ) {
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
            ?.map((v) => _parsePackageVersion(
                json['name'] as String, v as Map<String, dynamic>))
            .toList() ??
        [];

    return PackageInfo(package: package, versions: versions);
  }

  PackageVersion _parsePackageVersion(
    String packageName,
    Map<String, dynamic> json,
  ) {
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

  Future<List<SiteConfig>> getConfig() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/config'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch config: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final configs = (json['config'] as List<dynamic>?)
            ?.map((c) => SiteConfig.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];

    return configs;
  }

  Future<void> setConfig(String name, String value) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/admin/api/config/$name'),
      headers: _headers,
      body: jsonEncode({'value': value}),
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to update config: ${response.body}',
      );
    }
  }

  void dispose() {
    _client.close();
  }
}
