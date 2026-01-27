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

class UserListResponse {
  final List<User> users;
  final int total;
  final int page;
  final int limit;

  int get totalPages => (total / limit).ceil();
  bool get hasPrevPage => page > 1;
  bool get hasNextPage => page < totalPages;

  const UserListResponse({
    required this.users,
    required this.total,
    required this.page,
    required this.limit,
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
    // Dev mode: admin on different port, API on 4920
    if (location.port == '4922') {
      return '${location.protocol}//${location.hostname}:4920';
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

  /// Get comprehensive dashboard statistics including recent activity.
  /// This is a wrapper around getStats() that can be extended with more data.
  Future<Map<String, dynamic>> getDashboardStats() async {
    final stats = await getStats();

    // TODO: Add recent activity feed from backend
    // For now, return basic stats
    return {
      'totalPackages': stats.totalPackages,
      'localPackages': stats.localPackages,
      'cachedPackages': stats.cachedPackages,
      'totalVersions': stats.totalVersions,
      'recentActivity': <Map<String, dynamic>>[],
      'topPackages': <Map<String, dynamic>>[],
    };
  }

  Future<Map<String, int>> getPackagesCreatedPerDay({int days = 30}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/analytics/packages-created?days=$days'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch packages created analytics: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json.map((key, value) => MapEntry(key, value as int));
  }

  Future<Map<String, int>> getDownloadsPerHour({int hours = 24}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/analytics/downloads?hours=$hours'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch downloads analytics: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json.map((key, value) => MapEntry(key, value as int));
  }

  /// List hosted packages (packages published directly to this registry).
  Future<PackageListResponse> listHostedPackages({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/hosted-packages?page=$page&limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to list hosted packages: ${response.body}',
      );
    }

    return _parsePackageListResponse(response.body, page, limit);
  }

  /// List cached packages (packages cached from upstream registry).
  Future<PackageListResponse> listCachedPackages({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/cached-packages?page=$page&limit=$limit'),
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

  Future<UserListResponse> listUsers({
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/users?page=$page&limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to list users: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final users = (json['users'] as List<dynamic>?)
            ?.map((u) => User.fromJson(u as Map<String, dynamic>))
            .toList() ??
        [];

    return UserListResponse(
      users: users,
      total: json['total'] as int? ?? users.length,
      page: json['page'] as int? ?? page,
      limit: json['limit'] as int? ?? limit,
    );
  }

  Future<User> createUser({
    required String email,
    required String password,
    String? name,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/api/users'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        if (name != null) 'name': name,
      }),
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to create user: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<User> updateUser(
    String id, {
    String? name,
    String? password,
    bool? isActive,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/admin/api/users/$id'),
      headers: _headers,
      body: jsonEncode({
        if (name != null) 'name': name,
        if (password != null) 'password': password,
        if (isActive != null) 'isActive': isActive,
      }),
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to update user: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return User.fromJson(json['user'] as Map<String, dynamic>);
  }

  Future<void> deleteUser(String id) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/admin/api/users/$id'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to delete user: ${response.body}',
      );
    }
  }

  Future<List<UserToken>> getUserTokens(String userId) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/users/$userId/tokens'),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'User not found',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch user tokens: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final tokens = (json['tokens'] as List<dynamic>?)
            ?.map((t) => UserToken.fromJson(t as Map<String, dynamic>))
            .toList() ??
        [];

    return tokens;
  }

  Future<List<AdminUser>> listAdminUsers() async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/admin-users'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to list admin users: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final adminUsers = (json['adminUsers'] as List<dynamic>?)
            ?.map((u) => AdminUser.fromJson(u as Map<String, dynamic>))
            .toList() ??
        [];

    return adminUsers;
  }

  Future<AdminUserDetail> getAdminUser(String id) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/admin-users/$id'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch admin user: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final adminUser =
        AdminUser.fromJson(json['adminUser'] as Map<String, dynamic>);
    final recentLogins = (json['recentLogins'] as List<dynamic>?)
            ?.map((l) => AdminLoginHistory.fromJson(l as Map<String, dynamic>))
            .toList() ??
        [];

    return AdminUserDetail(adminUser: adminUser, recentLogins: recentLogins);
  }

  Future<List<AdminLoginHistory>> getAdminLoginHistory(String id) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/admin-users/$id/login-history'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch login history: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final loginHistory = (json['loginHistory'] as List<dynamic>?)
            ?.map((l) => AdminLoginHistory.fromJson(l as Map<String, dynamic>))
            .toList() ??
        [];

    return loginHistory;
  }

  void dispose() {
    _client.close();
  }
}

class AdminUserDetail {
  final AdminUser adminUser;
  final List<AdminLoginHistory> recentLogins;

  const AdminUserDetail({
    required this.adminUser,
    required this.recentLogins,
  });
}

/// Represents an API token for a user (admin view).
class UserToken {
  final String label;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;

  const UserToken({
    required this.label,
    required this.scopes,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  factory UserToken.fromJson(Map<String, dynamic> json) {
    return UserToken(
      label: json['label'] as String,
      scopes: (json['scopes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'] as String)
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
    );
  }

  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);
}
