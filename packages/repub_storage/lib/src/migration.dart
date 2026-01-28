import 'package:repub_model/repub_model.dart';

import 'blobs.dart';
import 'metadata.dart';

/// Progress callback for migration operations.
typedef MigrationProgressCallback = void Function(
  int current,
  int total,
  String key,
);

/// Result of a migration operation.
class MigrationResult {
  final int successful;
  final int failed;
  final int skipped;
  final List<String> errors;
  final Duration duration;

  MigrationResult({
    required this.successful,
    required this.failed,
    required this.skipped,
    required this.errors,
    required this.duration,
  });

  int get total => successful + failed + skipped;

  Map<String, dynamic> toJson() => {
        'successful': successful,
        'failed': failed,
        'skipped': skipped,
        'total': total,
        'durationSeconds': duration.inSeconds,
        'errors': errors,
      };

  @override
  String toString() => '''
Migration completed in ${duration.inSeconds}s:
  Successful: $successful
  Failed: $failed
  Skipped: $skipped
  Total: $total''';
}

/// Storage migration utilities.
///
/// Migrates package archives between storage backends (local <-> S3).
class StorageMigration {
  final MetadataStore metadata;
  final BlobStore sourceStore;
  final BlobStore targetStore;

  StorageMigration({
    required this.metadata,
    required this.sourceStore,
    required this.targetStore,
  });

  /// Create a migration from local storage to S3.
  static StorageMigration localToS3({
    required MetadataStore metadata,
    required Config config,
  }) {
    if (!config.useLocalStorage) {
      throw MigrationException(
        'Source must be local storage. Set REPUB_STORAGE_PATH.',
      );
    }
    if (!config.hasS3Config) {
      throw MigrationException(
        'Target must be S3. Configure S3 environment variables.',
      );
    }

    return StorageMigration(
      metadata: metadata,
      sourceStore: FileBlobStore(
        basePath: config.storagePath!,
        baseUrl: config.baseUrl,
      ),
      targetStore: S3BlobStore.fromConfig(config),
    );
  }

  /// Create a migration from S3 to local storage.
  static StorageMigration s3ToLocal({
    required MetadataStore metadata,
    required Config config,
    required String targetPath,
  }) {
    if (!config.hasS3Config) {
      throw MigrationException(
        'Source must be S3. Configure S3 environment variables.',
      );
    }

    return StorageMigration(
      metadata: metadata,
      sourceStore: S3BlobStore.fromConfig(config),
      targetStore: FileBlobStore(
        basePath: targetPath,
        baseUrl: config.baseUrl,
      ),
    );
  }

  /// Get all archive keys from the database.
  Future<List<String>> getArchiveKeys({bool localOnly = true}) async {
    final result = await metadata.listPackages(page: 1, limit: 10000);
    final keys = <String>[];

    for (final pkgInfo in result.packages) {
      // Skip cached packages if localOnly
      if (localOnly && pkgInfo.package.isUpstreamCache) continue;

      for (final version in pkgInfo.versions) {
        keys.add(version.archiveKey);
      }
    }

    return keys;
  }

  /// Preview migration (dry run).
  Future<Map<String, dynamic>> preview({bool localOnly = true}) async {
    final keys = await getArchiveKeys(localOnly: localOnly);

    var existsInSource = 0;
    var existsInTarget = 0;
    var toMigrate = 0;

    for (final key in keys) {
      final inSource = await sourceStore.exists(key);
      final inTarget = await targetStore.exists(key);

      if (inSource) existsInSource++;
      if (inTarget) existsInTarget++;
      if (inSource && !inTarget) toMigrate++;
    }

    return {
      'totalKeys': keys.length,
      'existsInSource': existsInSource,
      'existsInTarget': existsInTarget,
      'toMigrate': toMigrate,
      'alreadyMigrated': existsInTarget,
    };
  }

  /// Migrate all archives from source to target.
  ///
  /// Options:
  /// - [localOnly]: Only migrate local packages (skip cached upstream packages)
  /// - [overwrite]: Overwrite existing files in target
  /// - [onProgress]: Progress callback
  Future<MigrationResult> migrate({
    bool localOnly = true,
    bool overwrite = false,
    MigrationProgressCallback? onProgress,
  }) async {
    final startTime = DateTime.now();
    final keys = await getArchiveKeys(localOnly: localOnly);
    final errors = <String>[];

    var successful = 0;
    var failed = 0;
    var skipped = 0;

    for (var i = 0; i < keys.length; i++) {
      final key = keys[i];
      onProgress?.call(i + 1, keys.length, key);

      try {
        // Check if source exists
        final sourceExists = await sourceStore.exists(key);
        if (!sourceExists) {
          skipped++;
          continue;
        }

        // Check if target exists
        final targetExists = await targetStore.exists(key);
        if (targetExists && !overwrite) {
          skipped++;
          continue;
        }

        // Copy data
        final data = await sourceStore.getArchive(key);
        await targetStore.putArchive(key: key, data: data);
        successful++;
      } catch (e) {
        failed++;
        errors.add('$key: $e');
      }
    }

    final duration = DateTime.now().difference(startTime);

    return MigrationResult(
      successful: successful,
      failed: failed,
      skipped: skipped,
      errors: errors,
      duration: duration,
    );
  }

  /// Verify migration by comparing checksums.
  Future<Map<String, dynamic>> verify({bool localOnly = true}) async {
    final keys = await getArchiveKeys(localOnly: localOnly);

    var matched = 0;
    var mismatched = 0;
    var missingInSource = 0;
    var missingInTarget = 0;
    final mismatches = <String>[];

    for (final key in keys) {
      final sourceExists = await sourceStore.exists(key);
      final targetExists = await targetStore.exists(key);

      if (!sourceExists) {
        missingInSource++;
        continue;
      }

      if (!targetExists) {
        missingInTarget++;
        continue;
      }

      // Compare data
      final sourceData = await sourceStore.getArchive(key);
      final targetData = await targetStore.getArchive(key);

      if (sourceData.length == targetData.length) {
        var match = true;
        for (var i = 0; i < sourceData.length && match; i++) {
          if (sourceData[i] != targetData[i]) {
            match = false;
          }
        }
        if (match) {
          matched++;
        } else {
          mismatched++;
          mismatches.add(key);
        }
      } else {
        mismatched++;
        mismatches.add(
            '$key (size mismatch: ${sourceData.length} vs ${targetData.length})');
      }
    }

    return {
      'totalKeys': keys.length,
      'matched': matched,
      'mismatched': mismatched,
      'missingInSource': missingInSource,
      'missingInTarget': missingInTarget,
      'mismatches': mismatches,
    };
  }
}

/// Exception thrown during migration operations.
class MigrationException implements Exception {
  final String message;
  MigrationException(this.message);

  @override
  String toString() => 'MigrationException: $message';
}
