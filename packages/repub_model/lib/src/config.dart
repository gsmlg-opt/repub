import 'dart:io';

/// Application configuration loaded from environment variables.
class Config {
  final String listenAddr;
  final int listenPort;
  final String baseUrl;
  final String databaseUrl;

  /// Local file storage path. If set, local storage is used instead of S3.
  final String? storagePath;

  /// S3 configuration (optional if storagePath is set).
  final String? s3Endpoint;
  final String? s3Region;
  final String? s3AccessKey;
  final String? s3SecretKey;
  final String? s3Bucket;

  final bool requireDownloadAuth;
  final int signedUrlTtlSeconds;

  const Config({
    required this.listenAddr,
    required this.listenPort,
    required this.baseUrl,
    required this.databaseUrl,
    this.storagePath,
    this.s3Endpoint,
    this.s3Region,
    this.s3AccessKey,
    this.s3SecretKey,
    this.s3Bucket,
    required this.requireDownloadAuth,
    required this.signedUrlTtlSeconds,
  });

  /// Whether to use local file storage instead of S3.
  bool get useLocalStorage => storagePath != null && storagePath!.isNotEmpty;

  /// Whether S3 is properly configured.
  bool get hasS3Config =>
      s3Endpoint != null &&
      s3AccessKey != null &&
      s3SecretKey != null &&
      s3Bucket != null;

  /// Load configuration from environment variables.
  factory Config.fromEnv() {
    final listenAddrFull = _env('REPUB_LISTEN_ADDR', '0.0.0.0:8080');
    final parts = listenAddrFull.split(':');
    final addr = parts.length > 1 ? parts[0] : '0.0.0.0';
    final port = parts.length > 1 ? int.parse(parts[1]) : 8080;

    return Config(
      listenAddr: addr,
      listenPort: port,
      baseUrl: _env('REPUB_BASE_URL', 'http://localhost:8080'),
      databaseUrl: _env(
        'REPUB_DATABASE_URL',
        'postgres://repub:repub@localhost:5432/repub',
      ),
      storagePath: _envOptional('REPUB_STORAGE_PATH'),
      s3Endpoint: _envOptional('REPUB_S3_ENDPOINT'),
      s3Region: _envOptional('REPUB_S3_REGION'),
      s3AccessKey: _envOptional('REPUB_S3_ACCESS_KEY'),
      s3SecretKey: _envOptional('REPUB_S3_SECRET_KEY'),
      s3Bucket: _envOptional('REPUB_S3_BUCKET'),
      requireDownloadAuth: _envBool('REPUB_REQUIRE_DOWNLOAD_AUTH', false),
      signedUrlTtlSeconds: _envInt('REPUB_SIGNED_URL_TTL_SECONDS', 3600),
    );
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
