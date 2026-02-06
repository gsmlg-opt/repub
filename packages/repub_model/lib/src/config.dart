import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';

/// Database type enum.
enum DatabaseType { sqlite, postgresql }

/// Storage type enum.
enum StorageType {
  local,
  s3;

  static StorageType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'local':
        return StorageType.local;
      case 's3':
        return StorageType.s3;
      default:
        throw ArgumentError('Invalid storage type: $value');
    }
  }
}

/// Encryption utilities for sensitive configuration values.
class ConfigEncryption {
  static final _algorithm = AesGcm.with256bits();

  /// Encrypt a plaintext value using AES-256-GCM.
  /// Returns base64-encoded format: nonce:ciphertext:mac
  static Future<String> encrypt(String plaintext, String keyHex) async {
    final keyBytes = hex.decode(keyHex);
    final secretKey = SecretKey(keyBytes);

    // Generate random nonce
    final nonce = _algorithm.newNonce();

    // Encrypt
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );

    // Format: nonce:ciphertext:mac
    final nonceHex = hex.encode(nonce);
    final ciphertextHex = hex.encode(secretBox.cipherText);
    final macHex = hex.encode(secretBox.mac.bytes);

    return '$nonceHex:$ciphertextHex:$macHex';
  }

  /// Decrypt a value encrypted with encrypt().
  /// Input format: nonce:ciphertext:mac (all hex-encoded)
  static Future<String> decrypt(String encrypted, String keyHex) async {
    final parts = encrypted.split(':');
    if (parts.length != 3) {
      throw ArgumentError('Invalid encrypted value format');
    }

    final keyBytes = hex.decode(keyHex);
    final secretKey = SecretKey(keyBytes);

    final nonce = hex.decode(parts[0]);
    final cipherText = hex.decode(parts[1]);
    final macBytes = hex.decode(parts[2]);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decrypted = await _algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(decrypted);
  }

  /// Generate a random 256-bit key for encryption.
  /// Returns hex-encoded key string.
  static String generateKey() {
    final random = Random.secure();
    final bytes = Uint8List(32); // 256 bits
    for (var i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return hex.encode(bytes);
  }
}

/// Storage configuration model.
class StorageConfig {
  final bool initialized;
  final StorageType type;
  final String? localPath;
  final String? cachePath;
  final String? s3Endpoint;
  final String? s3Region;
  final String? s3AccessKey; // Decrypted value
  final String? s3SecretKey; // Decrypted value
  final String? s3Bucket;

  const StorageConfig({
    required this.initialized,
    required this.type,
    this.localPath,
    this.cachePath,
    this.s3Endpoint,
    this.s3Region,
    this.s3AccessKey,
    this.s3SecretKey,
    this.s3Bucket,
  });

  /// Create storage config from environment variables.
  factory StorageConfig.fromEnv() {
    final storagePath = Platform.environment['REPUB_STORAGE_PATH'];
    final useLocal = storagePath != null && storagePath.isNotEmpty;

    return StorageConfig(
      initialized: false,
      type: useLocal ? StorageType.local : StorageType.s3,
      localPath: storagePath ?? './data/storage',
      cachePath: Platform.environment['REPUB_CACHE_PATH'] ?? './data/cache',
      s3Endpoint: Platform.environment['REPUB_S3_ENDPOINT'],
      s3Region: Platform.environment['REPUB_S3_REGION'] ?? 'us-east-1',
      s3AccessKey: Platform.environment['REPUB_S3_ACCESS_KEY'],
      s3SecretKey: Platform.environment['REPUB_S3_SECRET_KEY'],
      s3Bucket: Platform.environment['REPUB_S3_BUCKET'],
    );
  }

  /// Create storage config from database values.
  /// Decrypts sensitive fields using the provided encryption key.
  static Future<StorageConfig> fromDatabase(
    Map<String, String> configs,
    String encryptionKey,
  ) async {
    final initialized = configs['storage_config_initialized'] == 'true';
    final type = StorageType.fromString(configs['storage_type'] ?? 'local');

    // Decrypt sensitive fields if they exist and are not empty
    String? s3AccessKey;
    String? s3SecretKey;

    final encryptedAccessKey = configs['storage_s3_access_key'] ?? '';
    if (encryptedAccessKey.isNotEmpty) {
      try {
        s3AccessKey = await ConfigEncryption.decrypt(
          encryptedAccessKey,
          encryptionKey,
        );
      } catch (e) {
        // If decryption fails, leave as null
        s3AccessKey = null;
      }
    }

    final encryptedSecretKey = configs['storage_s3_secret_key'] ?? '';
    if (encryptedSecretKey.isNotEmpty) {
      try {
        s3SecretKey = await ConfigEncryption.decrypt(
          encryptedSecretKey,
          encryptionKey,
        );
      } catch (e) {
        // If decryption fails, leave as null
        s3SecretKey = null;
      }
    }

    return StorageConfig(
      initialized: initialized,
      type: type,
      localPath: configs['storage_local_path'],
      cachePath: configs['storage_cache_path'],
      s3Endpoint: configs['storage_s3_endpoint'],
      s3Region: configs['storage_s3_region'],
      s3AccessKey: s3AccessKey,
      s3SecretKey: s3SecretKey,
      s3Bucket: configs['storage_s3_bucket'],
    );
  }

  /// Convert to database values for persistence.
  /// Encrypts sensitive fields using the provided encryption key.
  Future<Map<String, String>> toDatabaseValues(String encryptionKey) async {
    // Encrypt sensitive fields if they exist
    String encryptedAccessKey = '';
    String encryptedSecretKey = '';

    if (s3AccessKey != null && s3AccessKey!.isNotEmpty) {
      encryptedAccessKey = await ConfigEncryption.encrypt(
        s3AccessKey!,
        encryptionKey,
      );
    }

    if (s3SecretKey != null && s3SecretKey!.isNotEmpty) {
      encryptedSecretKey = await ConfigEncryption.encrypt(
        s3SecretKey!,
        encryptionKey,
      );
    }

    return {
      'storage_config_initialized': initialized.toString(),
      'storage_type': type.name,
      'storage_local_path': localPath ?? '',
      'storage_cache_path': cachePath ?? '',
      'storage_s3_endpoint': s3Endpoint ?? '',
      'storage_s3_region': s3Region ?? 'us-east-1',
      'storage_s3_access_key': encryptedAccessKey,
      'storage_s3_secret_key': encryptedSecretKey,
      'storage_s3_bucket': s3Bucket ?? '',
    };
  }

  /// Validate the storage configuration.
  bool isValid() {
    if (type == StorageType.local) {
      return localPath != null && localPath!.isNotEmpty;
    } else {
      return s3Endpoint != null &&
          s3Endpoint!.isNotEmpty &&
          s3AccessKey != null &&
          s3AccessKey!.isNotEmpty &&
          s3SecretKey != null &&
          s3SecretKey!.isNotEmpty &&
          s3Bucket != null &&
          s3Bucket!.isNotEmpty;
    }
  }

  /// Get validation errors.
  List<String> get validationErrors {
    final errors = <String>[];

    if (type == StorageType.local) {
      if (localPath == null || localPath!.isEmpty) {
        errors.add('Local storage path is required for local storage type');
      }
    } else {
      if (s3Endpoint == null || s3Endpoint!.isEmpty) {
        errors.add('S3 endpoint is required for S3 storage type');
      }
      if (s3AccessKey == null || s3AccessKey!.isEmpty) {
        errors.add('S3 access key is required for S3 storage type');
      }
      if (s3SecretKey == null || s3SecretKey!.isEmpty) {
        errors.add('S3 secret key is required for S3 storage type');
      }
      if (s3Bucket == null || s3Bucket!.isEmpty) {
        errors.add('S3 bucket is required for S3 storage type');
      }
    }

    return errors;
  }

  /// Create a copy with some fields replaced.
  StorageConfig copyWith({
    bool? initialized,
    StorageType? type,
    String? localPath,
    String? cachePath,
    String? s3Endpoint,
    String? s3Region,
    String? s3AccessKey,
    String? s3SecretKey,
    String? s3Bucket,
  }) {
    return StorageConfig(
      initialized: initialized ?? this.initialized,
      type: type ?? this.type,
      localPath: localPath ?? this.localPath,
      cachePath: cachePath ?? this.cachePath,
      s3Endpoint: s3Endpoint ?? this.s3Endpoint,
      s3Region: s3Region ?? this.s3Region,
      s3AccessKey: s3AccessKey ?? this.s3AccessKey,
      s3SecretKey: s3SecretKey ?? this.s3SecretKey,
      s3Bucket: s3Bucket ?? this.s3Bucket,
    );
  }
}

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

  /// Number of database connection retry attempts before failing.
  /// Default is 30 (with 1 second delay between retries).
  final int databaseRetryAttempts;

  /// Delay between database connection retry attempts in seconds.
  final int databaseRetryDelaySeconds;

  /// Maximum upload size in bytes (default: 100MB).
  /// Uploads exceeding this limit will be rejected with 413.
  final int maxUploadSizeBytes;

  /// Encryption key for sensitive configuration values (hex-encoded 256-bit key).
  /// Auto-generated if not provided via REPUB_ENCRYPTION_KEY environment variable.
  final String encryptionKey;

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
    this.databaseRetryAttempts = 30,
    this.databaseRetryDelaySeconds = 1,
    this.maxUploadSizeBytes = 100 * 1024 * 1024, // 100MB default
    required this.encryptionKey,
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
    final port = parts.length > 1 ? (int.tryParse(parts[1]) ?? 4920) : 4920;

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
      rateLimitRequests:
          _envInt('REPUB_RATE_LIMIT_REQUESTS', 0), // 0 = unlimited
      rateLimitWindowSeconds: _envInt('REPUB_RATE_LIMIT_WINDOW_SECONDS', 60),
      adminIpWhitelist:
          _parseIpWhitelist(_envOptional('REPUB_ADMIN_IP_WHITELIST')),
      databaseRetryAttempts: _envInt('REPUB_DATABASE_RETRY_ATTEMPTS', 30),
      databaseRetryDelaySeconds:
          _envInt('REPUB_DATABASE_RETRY_DELAY_SECONDS', 1),
      maxUploadSizeBytes:
          _envInt('REPUB_MAX_UPLOAD_SIZE_BYTES', 100 * 1024 * 1024),
      encryptionKey: _env(
        'REPUB_ENCRYPTION_KEY',
        ConfigEncryption.generateKey(),
      ),
    );
  }

  /// Create a config with storage settings from database.
  /// Merges base environment config with storage config from database.
  Config withStorageFromDb(StorageConfig dbStorage) {
    return Config(
      listenAddr: listenAddr,
      listenPort: listenPort,
      baseUrl: baseUrl,
      databaseUrl: databaseUrl,
      storagePath:
          dbStorage.type == StorageType.local ? dbStorage.localPath : null,
      cachePath: dbStorage.cachePath,
      s3Endpoint:
          dbStorage.type == StorageType.s3 ? dbStorage.s3Endpoint : null,
      s3Region: dbStorage.type == StorageType.s3 ? dbStorage.s3Region : null,
      s3AccessKey:
          dbStorage.type == StorageType.s3 ? dbStorage.s3AccessKey : null,
      s3SecretKey:
          dbStorage.type == StorageType.s3 ? dbStorage.s3SecretKey : null,
      s3Bucket: dbStorage.type == StorageType.s3 ? dbStorage.s3Bucket : null,
      requireDownloadAuth: requireDownloadAuth,
      requirePublishAuth: requirePublishAuth,
      signedUrlTtlSeconds: signedUrlTtlSeconds,
      upstreamUrl: upstreamUrl,
      enableUpstreamProxy: enableUpstreamProxy,
      rateLimitRequests: rateLimitRequests,
      rateLimitWindowSeconds: rateLimitWindowSeconds,
      adminIpWhitelist: adminIpWhitelist,
      databaseRetryAttempts: databaseRetryAttempts,
      databaseRetryDelaySeconds: databaseRetryDelaySeconds,
      maxUploadSizeBytes: maxUploadSizeBytes,
      encryptionKey: encryptionKey,
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
