import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:repub_model/repub_model.dart';

import '../models/webhook_info.dart';
import 'url_detector_stub.dart'
    if (dart.library.html) 'url_detector_web.dart';

class AdminStats {
  final int totalPackages;
  final int localPackages;
  final int cachedPackages;
  final int totalVersions;
  final int totalUsers;
  final int activeTokens;
  final int totalDownloads;

  const AdminStats({
    required this.totalPackages,
    required this.localPackages,
    required this.cachedPackages,
    required this.totalVersions,
    this.totalUsers = 0,
    this.activeTokens = 0,
    this.totalDownloads = 0,
  });

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
        totalPackages: json['totalPackages'] as int,
        localPackages: json['localPackages'] as int,
        cachedPackages: json['cachedPackages'] as int,
        totalVersions: json['totalVersions'] as int,
        totalUsers: json['totalUsers'] as int? ?? 0,
        activeTokens: json['activeTokens'] as int? ?? 0,
        totalDownloads: json['totalDownloads'] as int? ?? 0,
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

  /// Creates an AdminApiClient with optional baseUrl and http.Client.
  /// If baseUrl is null, it will be auto-detected from browser location.
  /// The httpClient parameter allows injecting a mock client for testing.
  AdminApiClient({String? baseUrl, http.Client? httpClient})
      : baseUrl = baseUrl ?? _detectBaseUrl(),
        _client = httpClient ?? http.Client();

  /// Creates an AdminApiClient for testing (no browser dependencies).
  factory AdminApiClient.forTesting({
    required String baseUrl,
    required http.Client httpClient,
  }) {
    return AdminApiClient(baseUrl: baseUrl, httpClient: httpClient);
  }

  static String _detectBaseUrl() {
    return createUrlDetector().detectBaseUrl();
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

    // Fetch recent activity from backend
    List<Map<String, dynamic>> recentActivity = [];
    try {
      final activities = await getRecentActivity(limit: 10);
      recentActivity = activities;
    } catch (e) {
      // Silently fail for activity - dashboard still works without it
    }

    return {
      'total_packages': stats.totalPackages,
      'local_packages': stats.localPackages,
      'cached_packages': stats.cachedPackages,
      'total_versions': stats.totalVersions,
      'total_users': stats.totalUsers,
      'total_downloads': stats.totalDownloads,
      'active_tokens': stats.activeTokens,
      'recent_activity': recentActivity,
      'top_packages': <Map<String, dynamic>>[],
    };
  }

  /// Get recent activity from the activity log.
  Future<List<Map<String, dynamic>>> getRecentActivity({int limit = 10}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/activity?limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch recent activity: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final activities = (json['activities'] as List<dynamic>?) ?? [];

    // Transform API response to dashboard format
    return activities.map((a) {
      final activity = a as Map<String, dynamic>;
      return {
        'id': activity['id'] as String,
        'type': activity['activityType'] as String,
        'description': _generateDescription(activity),
        'timestamp': activity['timestamp'] as String,
        'actor_email': activity['actorEmail'] as String?,
        'target_package': activity['targetId'] as String?,
      };
    }).toList();
  }

  /// Generate human-readable description from activity data.
  String _generateDescription(Map<String, dynamic> activity) {
    final activityType = activity['activityType'] as String;
    final actorName = activity['actorUsername'] as String? ??
        activity['actorEmail'] as String? ??
        'Unknown';
    final targetId = activity['targetId'] as String?;
    final metadata = activity['metadata'] as Map<String, dynamic>?;
    final version = metadata?['version'] as String?;

    switch (activityType) {
      case 'package_published':
        return '$actorName published $targetId ${version ?? ''}';
      case 'user_registered':
        return '${activity['actorEmail']} registered';
      case 'admin_login':
        return '${activity['actorUsername']} logged in to admin panel';
      case 'package_deleted':
        return '$actorName deleted package $targetId';
      case 'package_version_deleted':
        return '$actorName deleted $targetId $version';
      case 'user_created':
        return '$actorName created user $targetId';
      case 'user_deleted':
        return '$actorName deleted user $targetId';
      case 'config_updated':
        return '$actorName updated configuration';
      case 'cache_cleared':
        return '$actorName cleared package cache';
      default:
        return '$activityType by $actorName';
    }
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

  /// Get package download statistics.
  Future<Map<String, dynamic>> getPackageStats(String packageName,
      {int days = 30}) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/packages/$packageName/stats?days=$days'),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Package not found: $packageName',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch package stats: ${response.body}',
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Get dependency information for a package.
  Future<PackageDependencies> getPackageDependencies(
    String packageName, {
    int depth = 2,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/packages/$packageName/dependencies?depth=$depth'),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Package not found: $packageName',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch dependencies: ${response.body}',
      );
    }

    return PackageDependencies.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
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

  /// Clear a single cached package from the cache.
  Future<DeleteResult> clearCachedPackage(String name) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/admin/api/cached-packages/$name'),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Cached package not found: $name',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to clear cached package: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final success = json['success'] as Map<String, dynamic>;
    return DeleteResult(
      message: success['message'] as String,
      versionsDeleted: success['versionsDeleted'] as int? ?? 0,
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

  // ============ Webhook Management ============

  /// List all webhooks.
  Future<List<WebhookInfo>> listWebhooks({bool activeOnly = false}) async {
    final queryParams = activeOnly ? '?active_only=true' : '';
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/webhooks$queryParams'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to list webhooks: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final webhooks = (json['webhooks'] as List<dynamic>?)
            ?.map((w) => WebhookInfo.fromJson(w as Map<String, dynamic>))
            .toList() ??
        [];

    return webhooks;
  }

  /// Create a new webhook.
  Future<WebhookInfo> createWebhook({
    required String url,
    required List<String> events,
    String? secret,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/api/webhooks'),
      headers: _headers,
      body: jsonEncode({
        'url': url,
        'events': events,
        if (secret != null && secret.isNotEmpty) 'secret': secret,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to create webhook: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return WebhookInfo.fromJson(json['webhook'] as Map<String, dynamic>);
  }

  /// Update an existing webhook.
  Future<WebhookInfo> updateWebhook(
    String id, {
    String? url,
    List<String>? events,
    bool? isActive,
  }) async {
    final response = await _client.put(
      Uri.parse('$baseUrl/admin/api/webhooks/$id'),
      headers: _headers,
      body: jsonEncode({
        if (url != null) 'url': url,
        if (events != null) 'events': events,
        if (isActive != null) 'is_active': isActive,
      }),
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to update webhook: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return WebhookInfo.fromJson(json['webhook'] as Map<String, dynamic>);
  }

  /// Delete a webhook.
  Future<void> deleteWebhook(String id) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/admin/api/webhooks/$id'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to delete webhook: ${response.body}',
      );
    }
  }

  /// Test a webhook by sending a test event.
  Future<bool> testWebhook(String id) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/api/webhooks/$id/test'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to test webhook: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['success'] as bool? ?? false;
  }

  /// Get recent deliveries for a webhook.
  Future<List<WebhookDeliveryInfo>> getWebhookDeliveries(
    String webhookId, {
    int limit = 50,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/webhooks/$webhookId/deliveries?limit=$limit'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch webhook deliveries: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final deliveries = (json['deliveries'] as List<dynamic>?)
            ?.map((d) => WebhookDeliveryInfo.fromJson(d as Map<String, dynamic>))
            .toList() ??
        [];

    return deliveries;
  }

  // ============ Version Retraction ============

  /// Retract a package version with an optional message explaining why.
  Future<void> retractPackageVersion(
    String packageName,
    String version, {
    String? message,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl/admin/api/packages/$packageName/versions/$version/retract'),
      headers: _headers,
      body: message != null && message.isNotEmpty
          ? jsonEncode({'message': message})
          : null,
    );

    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Version not found: $packageName@$version',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to retract version: ${response.body}',
      );
    }
  }

  /// Un-retract a package version.
  Future<void> unretractPackageVersion(String packageName, String version) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl/admin/api/packages/$packageName/versions/$version/retract'),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Version not found: $packageName@$version',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to un-retract version: ${response.body}',
      );
    }
  }

  /// Get package versions with their metadata including retraction status.
  Future<List<VersionInfo>> getPackageVersions(String packageName) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/admin/api/packages/$packageName/versions'),
      headers: _headers,
    );

    if (response.statusCode == 404) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Package not found: $packageName',
      );
    }

    if (response.statusCode != 200) {
      throw AdminApiException(
        statusCode: response.statusCode,
        message: 'Failed to fetch versions: ${response.body}',
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final versions = (json['versions'] as List<dynamic>?)
            ?.map((v) => VersionInfo.fromJson(v as Map<String, dynamic>))
            .toList() ??
        [];

    return versions;
  }
}

/// Represents a package version with retraction metadata.
class VersionInfo {
  final String version;
  final DateTime publishedAt;
  final bool isRetracted;
  final DateTime? retractedAt;
  final String? retractionMessage;

  const VersionInfo({
    required this.version,
    required this.publishedAt,
    this.isRetracted = false,
    this.retractedAt,
    this.retractionMessage,
  });

  factory VersionInfo.fromJson(Map<String, dynamic> json) {
    return VersionInfo(
      version: json['version'] as String,
      publishedAt: DateTime.parse(json['published_at'] as String),
      isRetracted: json['is_retracted'] as bool? ?? false,
      retractedAt: json['retracted_at'] != null
          ? DateTime.parse(json['retracted_at'] as String)
          : null,
      retractionMessage: json['retraction_message'] as String?,
    );
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

/// Package dependency information.
class PackageDependencies {
  final String package;
  final String? version;
  final Map<String, dynamic> dependencies;
  final Map<String, dynamic> devDependencies;
  final List<ReverseDependency> reverseDependencies;
  final Map<String, dynamic> dependencyTree;
  final Map<String, dynamic> environment;

  const PackageDependencies({
    required this.package,
    this.version,
    required this.dependencies,
    required this.devDependencies,
    required this.reverseDependencies,
    required this.dependencyTree,
    required this.environment,
  });

  factory PackageDependencies.fromJson(Map<String, dynamic> json) {
    return PackageDependencies(
      package: json['package'] as String,
      version: json['version'] as String?,
      dependencies:
          (json['dependencies'] as Map<String, dynamic>?) ?? {},
      devDependencies:
          (json['dev_dependencies'] as Map<String, dynamic>?) ?? {},
      reverseDependencies: (json['reverse_dependencies'] as List<dynamic>?)
              ?.map((e) => ReverseDependency.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      dependencyTree:
          (json['dependency_tree'] as Map<String, dynamic>?) ?? {},
      environment:
          (json['environment'] as Map<String, dynamic>?) ?? {},
    );
  }

  int get totalDependencies => dependencies.length;
  int get totalDevDependencies => devDependencies.length;
  int get totalReverseDependencies => reverseDependencies.length;
}

/// A package that depends on another package.
class ReverseDependency {
  final String name;
  final String version;
  final dynamic constraint;
  final String type;

  const ReverseDependency({
    required this.name,
    required this.version,
    required this.constraint,
    required this.type,
  });

  factory ReverseDependency.fromJson(Map<String, dynamic> json) {
    return ReverseDependency(
      name: json['name'] as String,
      version: json['version'] as String,
      constraint: json['constraint'],
      type: json['type'] as String,
    );
  }

  bool get isDevDependency => type == 'dev_dependency';
}
