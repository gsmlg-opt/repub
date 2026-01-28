import 'dart:io';

import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';

/// Handle storage sub-commands.
Future<void> storageCommands(List<String> args) async {
  if (args.isEmpty) {
    _printStorageUsage();
    exit(1);
  }

  final command = args.first;
  final subArgs = args.length > 1 ? args.sublist(1) : <String>[];

  switch (command) {
    case 'migrate':
      await _runMigrate(subArgs);
    case 'verify':
      await _runVerify(subArgs);
    case 'help':
    case '--help':
    case '-h':
      _printStorageUsage();
    default:
      Logger.error('Unknown storage command', component: 'cli', metadata: {'command': command});
      print('Unknown storage command: $command');
      _printStorageUsage();
      exit(1);
  }
}

void _printStorageUsage() {
  print('''
Storage Migration Commands

Usage:
  dart run repub_cli storage <command> [options]

Commands:
  migrate <direction>   Migrate package archives between storage backends
  verify <direction>    Verify migration integrity
  help                  Show this help message

Migration Directions:
  local-to-s3          Migrate from local storage to S3
  s3-to-local          Migrate from S3 to local storage

Examples:
  # Preview migration from local to S3
  dart run repub_cli storage migrate local-to-s3 --dry-run

  # Migrate from local to S3
  dart run repub_cli storage migrate local-to-s3

  # Migrate from S3 to local (specify target path)
  dart run repub_cli storage migrate s3-to-local --target ./data/packages

  # Verify migration
  dart run repub_cli storage verify local-to-s3

Options for migrate:
  --dry-run            Preview without making changes
  --overwrite          Overwrite existing files in target
  --include-cache      Include cached upstream packages
  --target <path>      Target path for s3-to-local migration

Environment Variables:
  REPUB_STORAGE_PATH   Local storage path (source for local-to-s3)
  REPUB_S3_ENDPOINT    S3 endpoint
  REPUB_S3_ACCESS_KEY  S3 access key
  REPUB_S3_SECRET_KEY  S3 secret key
  REPUB_S3_BUCKET      S3 bucket name
  REPUB_S3_REGION      S3 region (default: us-east-1)

Note:
  - For local-to-s3: Set REPUB_STORAGE_PATH and S3 variables
  - For s3-to-local: Set S3 variables and use --target flag
''');
}

Future<void> _runMigrate(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final overwrite = args.contains('--overwrite');
  final includeCache = args.contains('--include-cache');

  final directionArgs = args.where((a) => !a.startsWith('--')).toList();
  final targetIndex = args.indexOf('--target');
  String? targetPath;
  if (targetIndex != -1 && targetIndex + 1 < args.length) {
    targetPath = args[targetIndex + 1];
    directionArgs.remove(targetPath);
  }

  if (directionArgs.isEmpty) {
    Logger.error('Missing migration direction', component: 'cli');
    print('Error: Missing migration direction');
    print(
        'Usage: dart run repub_cli storage migrate <local-to-s3|s3-to-local>');
    exit(1);
  }

  final direction = directionArgs.first;
  final config = Config.fromEnv();

  print('Connecting to database...');
  final metadata = await MetadataStore.create(config);
  await metadata.runMigrations();

  StorageMigration migration;
  try {
    switch (direction) {
      case 'local-to-s3':
        print('Migration: Local -> S3');
        print('Source: ${config.storagePath}');
        print('Target: ${config.s3Bucket} (${config.s3Endpoint})');
        migration = StorageMigration.localToS3(
          metadata: metadata,
          config: config,
        );
        break;

      case 's3-to-local':
        if (targetPath == null) {
          Logger.error('Target path required for s3-to-local migration', component: 'cli');
          print('Error: --target <path> is required for s3-to-local migration');
          exit(1);
        }
        print('Migration: S3 -> Local');
        print('Source: ${config.s3Bucket} (${config.s3Endpoint})');
        print('Target: $targetPath');
        migration = StorageMigration.s3ToLocal(
          metadata: metadata,
          config: config,
          targetPath: targetPath,
        );
        break;

      default:
        Logger.error('Invalid migration direction', component: 'cli', metadata: {'direction': direction});
        print('Error: Invalid direction. Use "local-to-s3" or "s3-to-local"');
        exit(1);
    }

    // Ensure target is ready
    await migration.targetStore.ensureReady();

    // Preview
    print('');
    print('Scanning archives...');
    final preview = await migration.preview(localOnly: !includeCache);
    print('');
    print('Preview:');
    print('  Total archives: ${preview['totalKeys']}');
    print('  In source: ${preview['existsInSource']}');
    print('  In target: ${preview['existsInTarget']}');
    print('  To migrate: ${preview['toMigrate']}');

    if (dryRun) {
      print('');
      print('Dry run complete. No changes were made.');
      await metadata.close();
      return;
    }

    if (preview['toMigrate'] == 0) {
      print('');
      print('Nothing to migrate.');
      await metadata.close();
      return;
    }

    // Confirm
    print('');
    stdout.write('Continue with migration? [y/N]: ');
    final input = (stdin.readLineSync() ?? '').toLowerCase();
    if (input != 'y' && input != 'yes') {
      print('Migration cancelled.');
      await metadata.close();
      exit(0);
    }

    // Migrate
    print('');
    print('Migrating...');
    final result = await migration.migrate(
      localOnly: !includeCache,
      overwrite: overwrite,
      onProgress: (current, total, key) {
        stdout.write('\r  $current/$total: $key');
      },
    );

    print('');
    print('');
    print(result);

    if (result.errors.isNotEmpty) {
      print('');
      print('Errors:');
      for (final error in result.errors.take(10)) {
        print('  $error');
      }
      if (result.errors.length > 10) {
        print('  ... and ${result.errors.length - 10} more errors');
      }
    }

    await metadata.close();
  } on MigrationException catch (e) {
    Logger.error('Migration failed', component: 'cli', metadata: {'error': e.message});
    print('');
    print('Error: ${e.message}');
    await metadata.close();
    exit(1);
  } catch (e) {
    Logger.error('Migration failed with unexpected error', component: 'cli', metadata: {'error': e.toString()});
    print('');
    print('Error: $e');
    await metadata.close();
    exit(1);
  }
}

Future<void> _runVerify(List<String> args) async{
  final includeCache = args.contains('--include-cache');
  final directionArgs = args.where((a) => !a.startsWith('--')).toList();

  final targetIndex = args.indexOf('--target');
  String? targetPath;
  if (targetIndex != -1 && targetIndex + 1 < args.length) {
    targetPath = args[targetIndex + 1];
    directionArgs.remove(targetPath);
  }

  if (directionArgs.isEmpty) {
    Logger.error('Missing migration direction for verification', component: 'cli');
    print('Error: Missing migration direction');
    print('Usage: dart run repub_cli storage verify <local-to-s3|s3-to-local>');
    exit(1);
  }

  final direction = directionArgs.first;
  final config = Config.fromEnv();

  print('Connecting to database...');
  final metadata = await MetadataStore.create(config);
  await metadata.runMigrations();

  StorageMigration migration;
  try {
    switch (direction) {
      case 'local-to-s3':
        print('Verifying: Local -> S3');
        migration = StorageMigration.localToS3(
          metadata: metadata,
          config: config,
        );
        break;

      case 's3-to-local':
        if (targetPath == null) {
          Logger.error('Target path required for s3-to-local verification', component: 'cli');
          print(
              'Error: --target <path> is required for s3-to-local verification');
          exit(1);
        }
        print('Verifying: S3 -> Local ($targetPath)');
        migration = StorageMigration.s3ToLocal(
          metadata: metadata,
          config: config,
          targetPath: targetPath,
        );
        break;

      default:
        Logger.error('Invalid verification direction', component: 'cli', metadata: {'direction': direction});
        print('Error: Invalid direction. Use "local-to-s3" or "s3-to-local"');
        exit(1);
    }

    print('');
    print('Verifying...');
    final result = await migration.verify(localOnly: !includeCache);

    print('');
    print('Verification Results:');
    print('  Total archives: ${result['totalKeys']}');
    print('  Matched: ${result['matched']}');
    print('  Mismatched: ${result['mismatched']}');
    print('  Missing in source: ${result['missingInSource']}');
    print('  Missing in target: ${result['missingInTarget']}');

    final mismatches = result['mismatches'] as List<String>;
    if (mismatches.isNotEmpty) {
      print('');
      print('Mismatches:');
      for (final mismatch in mismatches.take(10)) {
        print('  $mismatch');
      }
      if (mismatches.length > 10) {
        print('  ... and ${mismatches.length - 10} more');
      }
    }

    await metadata.close();

    if (result['mismatched'] > 0 || result['missingInTarget'] > 0) {
      exit(1);
    }
  } on MigrationException catch (e) {
    Logger.error('Verification failed', component: 'cli', metadata: {'error': e.message});
    print('');
    print('Error: ${e.message}');
    await metadata.close();
    exit(1);
  } catch (e) {
    Logger.error('Verification failed with unexpected error', component: 'cli', metadata: {'error': e.toString()});
    print('');
    print('Error: $e');
    await metadata.close();
    exit(1);
  }
}
