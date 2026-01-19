import 'dart:typed_data';

import 'package:minio/minio.dart';
import 'package:repub_model/repub_model.dart';

/// Blob storage backed by S3-compatible object storage.
class BlobStore {
  final Minio _minio;
  final String _bucket;
  final int _signedUrlTtl;

  BlobStore._({
    required Minio minio,
    required String bucket,
    required int signedUrlTtl,
  })  : _minio = minio,
        _bucket = bucket,
        _signedUrlTtl = signedUrlTtl;

  /// Create a blob store from config.
  factory BlobStore.fromConfig(Config config) {
    final endpoint = Uri.parse(config.s3Endpoint);

    final minio = Minio(
      endPoint: endpoint.host,
      port: endpoint.hasPort
          ? endpoint.port
          : (endpoint.scheme == 'https' ? 443 : 9000),
      useSSL: endpoint.scheme == 'https',
      accessKey: config.s3AccessKey,
      secretKey: config.s3SecretKey,
      region: config.s3Region,
    );

    return BlobStore._(
      minio: minio,
      bucket: config.s3Bucket,
      signedUrlTtl: config.signedUrlTtlSeconds,
    );
  }

  /// Ensure the bucket exists.
  Future<void> ensureBucket() async {
    final exists = await _minio.bucketExists(_bucket);
    if (!exists) {
      await _minio.makeBucket(_bucket);
      print('Created bucket: $_bucket');
    }
  }

  /// Generate the storage key for a package archive.
  String archiveKey(String packageName, String version, String sha256) {
    return 'packages/$packageName/$version/$sha256.tar.gz';
  }

  /// Upload a package archive.
  Future<void> putArchive({
    required String key,
    required Uint8List data,
    String contentType = 'application/gzip',
  }) async {
    await _minio.putObject(
      _bucket,
      key,
      Stream.value(data),
      size: data.length,
      metadata: {'content-type': contentType},
    );
  }

  /// Get a presigned URL for downloading an archive.
  Future<String> getSignedUrl(String key) async {
    return await _minio.presignedGetObject(
      _bucket,
      key,
      expires: _signedUrlTtl,
    );
  }

  /// Get the raw bytes of an archive (for streaming endpoint).
  Future<Uint8List> getArchive(String key) async {
    final stream = await _minio.getObject(_bucket, key);
    final chunks = <int>[];
    await for (final chunk in stream) {
      chunks.addAll(chunk);
    }
    return Uint8List.fromList(chunks);
  }

  /// Check if an object exists.
  Future<bool> exists(String key) async {
    try {
      await _minio.statObject(_bucket, key);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Delete an object.
  Future<void> delete(String key) async {
    await _minio.removeObject(_bucket, key);
  }
}
