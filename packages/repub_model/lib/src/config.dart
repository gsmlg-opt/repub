import 'dart:io';

/// Application configuration loaded from environment variables.
class Config {
  final String listenAddr;
  final int listenPort;
  final String baseUrl;
  final String databaseUrl;
  final String s3Endpoint;
  final String s3Region;
  final String s3AccessKey;
  final String s3SecretKey;
  final String s3Bucket;
  final bool requireDownloadAuth;
  final int signedUrlTtlSeconds;

  const Config({
    required this.listenAddr,
    required this.listenPort,
    required this.baseUrl,
    required this.databaseUrl,
    required this.s3Endpoint,
    required this.s3Region,
    required this.s3AccessKey,
    required this.s3SecretKey,
    required this.s3Bucket,
    required this.requireDownloadAuth,
    required this.signedUrlTtlSeconds,
  });

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
      s3Endpoint: _env('REPUB_S3_ENDPOINT', 'http://localhost:9000'),
      s3Region: _env('REPUB_S3_REGION', 'us-east-1'),
      s3AccessKey: _env('REPUB_S3_ACCESS_KEY', 'minioadmin'),
      s3SecretKey: _env('REPUB_S3_SECRET_KEY', 'minioadmin'),
      s3Bucket: _env('REPUB_S3_BUCKET', 'repub'),
      requireDownloadAuth: _envBool('REPUB_REQUIRE_DOWNLOAD_AUTH', false),
      signedUrlTtlSeconds: _envInt('REPUB_SIGNED_URL_TTL_SECONDS', 3600),
    );
  }

  static String _env(String key, String defaultValue) {
    return Platform.environment[key] ?? defaultValue;
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
