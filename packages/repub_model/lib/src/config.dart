import 'dart:io';

/// Database type enum.
enum DatabaseType { sqlite, postgresql }

/// Application configuration loaded from environment variables.
class Config {
  final String listenAddr;
  final int listenPort;
  final String baseUrl;
  final String databaseUrl;

  /// Local file storage path. If set, local storage is used instead of S3.
  final String? storagePath;

  /// Cache storage path for upstream packages.
  /// If not set, defaults to `storagePath/cache` when using local storage.
  final String? cachePath;

  /// S3 configuration (optional if storagePath is set).
  final String? s3Endpoint;
  final String? s3Region;
  final String? s3AccessKey;
  final String? s3SecretKey;
  final String? s3Bucket;

  final bool requireDownloadAuth;
  final bool requirePublishAuth;
  final int signedUrlTtlSeconds;

  /// Upstream pub server URL for caching proxy mode.
  /// When a package is not found locally, it will be fetched from upstream.
  final String upstreamUrl;

  /// Whether to enable upstream proxy/caching.
  final bool enableUpstreamProxy;

  /// Rate limiting: max requests per window.
  final int rateLimitRequests;

  /// Rate limiting: window duration in seconds.
  final int rateLimitWindowSeconds;

  /// IP whitelist for admin panel access.
  /// When non-empty, only these IPs/CIDRs can access /admin/* endpoints.
  /// Supports IPv4 addresses, IPv4 CIDRs (e.g., 192.168.1.0/24),
  /// and special values like 'localhost' (expands to 127.0.0.1).
  final List<String> adminIpWhitelist;

  const Config({
    required this.listenAddr,
    required this.listenPort,
    required this.baseUrl,
    required this.databaseUrl,
    this.storagePath,
    this.cachePath,
    this.s3Endpoint,
    this.s3Region,
    this.s3AccessKey,
    this.s3SecretKey,
    this.s3Bucket,
    required this.requireDownloadAuth,
    required this.requirePublishAuth,
    required this.signedUrlTtlSeconds,
    required this.upstreamUrl,
    required this.enableUpstreamProxy,
    required this.rateLimitRequests,
    required this.rateLimitWindowSeconds,
    this.adminIpWhitelist = const [],
  });

  /// Get the database type based on the URL scheme.
  DatabaseType get databaseType {
    if (databaseUrl.startsWith('postgres://') ||
        databaseUrl.startsWith('postgresql://')) {
      return DatabaseType.postgresql;
    }
    // Default to SQLite (file path or sqlite:// scheme)
    return DatabaseType.sqlite;
  }

  /// Get the SQLite database path (strips sqlite:// prefix if present).
  String get sqlitePath {
    if (databaseUrl.startsWith('sqlite://')) {
      return databaseUrl.substring(9);
    }
    if (databaseUrl.startsWith('sqlite:')) {
      return databaseUrl.substring(7);
    }
    return databaseUrl;
  }

  /// Whether to use local file storage instead of S3.
  bool get useLocalStorage => storagePath != null && storagePath!.isNotEmpty;

  /// Whether S3 is properly configured.
  bool get hasS3Config =>
      s3Endpoint != null &&
      s3AccessKey != null &&
      s3SecretKey != null &&
      s3Bucket != null;

  /// Get the effective cache path for storing upstream packages.
  /// Returns the configured cachePath (defaults to ./data/cache).
  String get effectiveCachePath => cachePath!;

  /// Load configuration from environment variables.
  factory Config.fromEnv() {
    final listenAddrFull = _env('REPUB_LISTEN_ADDR', '0.0.0.0:4920');
    final parts = listenAddrFull.split(':');
    final addr = parts.length > 1 ? parts[0] : '0.0.0.0';
    final port = parts.length > 1 ? int.parse(parts[1]) : 4920;

    return Config(
      listenAddr: addr,
      listenPort: port,
      baseUrl: _env('REPUB_BASE_URL', 'http://localhost:4920'),
      databaseUrl: _env(
        'REPUB_DATABASE_URL',
        'sqlite:./data/repub.db',
      ),
      storagePath: _envOptional('REPUB_STORAGE_PATH'),
      cachePath: _env('REPUB_CACHE_PATH', './data/cache'),
      s3Endpoint: _envOptional('REPUB_S3_ENDPOINT'),
      s3Region: _envOptional('REPUB_S3_REGION'),
      s3AccessKey: _envOptional('REPUB_S3_ACCESS_KEY'),
      s3SecretKey: _envOptional('REPUB_S3_SECRET_KEY'),
      s3Bucket: _envOptional('REPUB_S3_BUCKET'),
      requireDownloadAuth: _envBool('REPUB_REQUIRE_DOWNLOAD_AUTH', false),
      requirePublishAuth: _envBool('REPUB_REQUIRE_PUBLISH_AUTH', false),
      signedUrlTtlSeconds: _envInt('REPUB_SIGNED_URL_TTL_SECONDS', 3600),
      upstreamUrl: _env('REPUB_UPSTREAM_URL', 'https://pub.dev'),
      enableUpstreamProxy: _envBool('REPUB_ENABLE_UPSTREAM_PROXY', true),
      rateLimitRequests: _envInt('REPUB_RATE_LIMIT_REQUESTS', 100),
      rateLimitWindowSeconds: _envInt('REPUB_RATE_LIMIT_WINDOW_SECONDS', 60),
      adminIpWhitelist: _parseIpWhitelist(_envOptional('REPUB_ADMIN_IP_WHITELIST')),
    );
  }

  /// Parse comma-separated IP whitelist from environment variable.
  static List<String> _parseIpWhitelist(String? value) {
    if (value == null || value.isEmpty) return [];
    return value
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  static String _env(String key, String defaultValue) {
    return Platform.environment[key] ?? defaultValue;
  }

  static String? _envOptional(String key) {
    final value = Platform.environment[key];
    return (value != null && value.isNotEmpty) ? value : null;
  }

  static bool _envBool(String key, bool defaultValue) {
    final value = Platform.environment[key];
    if (value == null) return defaultValue;
    return value.toLowerCase() == 'true' || value == '1';
  }

  static int _envInt(String key, int defaultValue) {
    final value = Platform.environment[key];
    if (value == null) return defaultValue;
    return int.tryParse(value) ?? defaultValue;
  }
}
