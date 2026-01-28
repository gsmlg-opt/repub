import 'dart:io';
import 'dart:typed_data';

import 'package:minio/minio.dart';
import 'package:path/path.dart' as p;
import 'package:repub_model/repub_model.dart';

/// Abstract blob storage interface.
abstract class BlobStore {
  /// Create a blob store from config for local packages.
  /// Uses local file storage if REPUB_STORAGE_PATH is set,
  /// otherwise uses S3-compatible storage.
  factory BlobStore.fromConfig(Config config) {
    if (config.useLocalStorage) {
      return FileBlobStore(
        basePath: config.storagePath!,
        baseUrl: config.baseUrl,
      );
    }

    if (!config.hasS3Config) {
      throw ArgumentError(
        'Either REPUB_STORAGE_PATH or S3 configuration '
        '(REPUB_S3_ENDPOINT, REPUB_S3_ACCESS_KEY, REPUB_S3_SECRET_KEY, '
        'REPUB_S3_BUCKET) must be provided.',
      );
    }

    return S3BlobStore.fromConfig(config);
  }

  /// Create a blob store for cached upstream packages.
  /// Uses effectiveCachePath for local storage (defaults to ./data/cache),
  /// or S3 with 'cache/' prefix if S3 is configured and no local path set.
  factory BlobStore.cacheFromConfig(Config config) {
    // Always use local file storage for cache (has default ./data/cache)
    return FileBlobStore(
      basePath: config.effectiveCachePath,
      baseUrl: config.baseUrl,
      isCache: true,
    );
  }

  /// Ensure storage is ready (bucket exists, directory created, etc).
  Future<void> ensureReady();

  /// Generate the storage key for a package archive.
  String archiveKey(String packageName, String version, String sha256);

  /// Upload a package archive.
  Future<void> putArchive({
    required String key,
    required Uint8List data,
    String contentType = 'application/gzip',
  });

  /// Get a URL for downloading an archive.
  /// For S3, this returns a presigned URL.
  /// For local storage, this returns the server's download endpoint.
  Future<String> getDownloadUrl(String key);

  /// Get the raw bytes of an archive.
  Future<Uint8List> getArchive(String key);

  /// Check if an object exists.
  Future<bool> exists(String key);

  /// Delete an object.
  Future<void> delete(String key);
}

/// Blob storage backed by S3-compatible object storage.
class S3BlobStore implements BlobStore {
  final Minio _minio;
  final String _bucket;
  final int _signedUrlTtl;
  final String _keyPrefix;

  S3BlobStore._({
    required Minio minio,
    required String bucket,
    required int signedUrlTtl,
    String keyPrefix = '',
  })  : _minio = minio,
        _bucket = bucket,
        _signedUrlTtl = signedUrlTtl,
        _keyPrefix = keyPrefix;

  /// Create a blob store from config.
  factory S3BlobStore.fromConfig(Config config, {String keyPrefix = ''}) {
    final endpoint = Uri.parse(config.s3Endpoint!);

    final minio = Minio(
      endPoint: endpoint.host,
      port: endpoint.hasPort
          ? endpoint.port
          : (endpoint.scheme == 'https' ? 443 : 9000),
      useSSL: endpoint.scheme == 'https',
      accessKey: config.s3AccessKey!,
      secretKey: config.s3SecretKey!,
      region: config.s3Region ?? 'us-east-1',
    );

    return S3BlobStore._(
      minio: minio,
      bucket: config.s3Bucket!,
      signedUrlTtl: config.signedUrlTtlSeconds,
      keyPrefix: keyPrefix,
    );
  }

  String _prefixedKey(String key) => '$_keyPrefix$key';

  @override
  Future<void> ensureReady() async {
    final exists = await _minio.bucketExists(_bucket);
    if (!exists) {
      await _minio.makeBucket(_bucket);
      Logger.info('Created S3 bucket',
          component: 'storage', metadata: {'bucket': _bucket});
    }
  }

  @override
  String archiveKey(String packageName, String version, String sha256) {
    return 'packages/$packageName/$version/$sha256.tar.gz';
  }

  @override
  Future<void> putArchive({
    required String key,
    required Uint8List data,
    String contentType = 'application/gzip',
  }) async {
    await _minio.putObject(
      _bucket,
      _prefixedKey(key),
      Stream.value(data),
      size: data.length,
      metadata: {'content-type': contentType},
    );
  }

  @override
  Future<String> getDownloadUrl(String key) async {
    return await _minio.presignedGetObject(
      _bucket,
      _prefixedKey(key),
      expires: _signedUrlTtl,
    );
  }

  @override
  Future<Uint8List> getArchive(String key) async {
    final stream = await _minio.getObject(_bucket, _prefixedKey(key));
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  @override
  Future<bool> exists(String key) async {
    try {
      await _minio.statObject(_bucket, _prefixedKey(key));
      return true;
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      // Object not found - return false
      if (errorStr.contains('not found') ||
          errorStr.contains('nosuchkey') ||
          errorStr.contains('404') ||
          errorStr.contains('does not exist')) {
        return false;
      }
      // Unexpected S3 error - log for debugging
      Logger.error(
        'S3 exists check failed with unexpected error',
        component: 'storage',
        error: e,
        metadata: {'key': key, 'bucket': _bucket},
      );
      // Rethrow to let caller handle (don't silently return false)
      rethrow;
    }
  }

  @override
  Future<void> delete(String key) async {
    await _minio.removeObject(_bucket, _prefixedKey(key));
  }
}

/// Blob storage backed by local file system.
class FileBlobStore implements BlobStore {
  final String _basePath;
  final String _baseUrl;
  final bool _isCache;

  FileBlobStore({
    required String basePath,
    required String baseUrl,
    bool isCache = false,
  })  : _basePath = basePath,
        _baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _isCache = isCache;

  @override
  Future<void> ensureReady() async {
    final dir = Directory(_basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      final storageType = _isCache ? 'cache' : 'storage';
      Logger.info('Created $storageType directory',
          component: 'storage', metadata: {'path': _basePath});
    }
  }

  @override
  String archiveKey(String packageName, String version, String sha256) {
    return 'packages/$packageName/$version/$sha256.tar.gz';
  }

  String _filePath(String key) => p.join(_basePath, key);

  @override
  Future<void> putArchive({
    required String key,
    required Uint8List data,
    String contentType = 'application/gzip',
  }) async {
    final file = File(_filePath(key));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  @override
  Future<String> getDownloadUrl(String key) async {
    // Return the server's download endpoint URL
    // The key format is: packages/<name>/<version>/<sha256>.tar.gz
    // We need to extract name and version for the API endpoint
    final parts = key.split('/');
    if (parts.length >= 3 && parts[0] == 'packages') {
      final name = parts[1];
      final version = parts[2];
      return '$_baseUrl/api/packages/$name/versions/$version/archive.tar.gz';
    }
    // Fallback: return direct path (won't work but indicates an error)
    return '$_baseUrl/storage/$key';
  }

  @override
  Future<Uint8List> getArchive(String key) async {
    final file = File(_filePath(key));
    return await file.readAsBytes();
  }

  @override
  Future<bool> exists(String key) async {
    return await File(_filePath(key)).exists();
  }

  @override
  Future<void> delete(String key) async {
    final file = File(_filePath(key));
    if (await file.exists()) {
      await file.delete();
    }
  }
}
