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
    case 'show':
      await _runShow(subArgs);
    case 'activate':
      await _runActivate(subArgs);
    case 'migrate':
      await _runMigrate(subArgs);
    case 'verify':
      await _runVerify(subArgs);
    case 'help':
    case '--help':
    case '-h':
      _printStorageUsage();
    default:
      Logger.error('Unknown storage command',
          component: 'cli', metadata: {'command': command});
      print('Unknown storage command: $command');
      _printStorageUsage();
      exit(1);
  }
}

void _printStorageUsage() {
  print('''
Storage Configuration & Migration Commands

Usage:
  dart run repub_cli storage <command> [options]

Configuration Commands:
  show                 Display current and pending storage configuration
  activate             Activate pending storage configuration (server must be stopped)

Migration Commands:
  migrate <direction>  Migrate package archives between storage backends
  verify <direction>   Verify migration integrity

Other:
  help                 Show this help message

Migration Directions:
  local-to-s3         Migrate from local storage to S3
  s3-to-local         Migrate from S3 to local storage

Configuration Workflow:
  1. Edit storage configuration in Admin UI (saves as pending)
  2. Stop the server
  3. Run: dart run repub_cli storage activate
  4. Migrate data if storage type changed: dart run repub_cli storage migrate <direction>
  5. Start the server

Examples:
  # Show current and pending storage configuration
  dart run repub_cli storage show

  # Activate pending configuration (server must be stopped)
  dart run repub_cli storage activate

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
  REPUB_DATABASE_URL       Database connection string
  REPUB_ENCRYPTION_KEY     Encryption key for sensitive values

WARNING:
  - Server MUST be stopped before activating configuration changes
  - After changing storage type, you MUST migrate data
  - Failure to migrate data will result in data loss

Note:
  - Configuration is stored in the database (encrypted for S3 credentials)
  - For first-time setup, environment variables are used (server initializes DB)
  - For runtime changes, edit in Admin UI then activate via CLI
''');
}

/// Show current and pending storage configuration from database.
Future<void> _runShow(List<String> args) async {
  Logger.init();
  final config = Config.fromEnv();

  print('Connecting to database...');
  final metadata = await MetadataStore.create(config);
  await metadata.runMigrations();

  try {
    final activeConfig = await metadata.getStorageConfig(config.encryptionKey);
    final pendingConfig =
        await metadata.getPendingStorageConfig(config.encryptionKey);

    // Show active configuration
    print('');
    print('═══ ACTIVE Storage Configuration ═══');
    if (activeConfig == null || !activeConfig.initialized) {
      print('');
      print('Not initialized in database.');
      print(
          'The server will initialize it from environment variables on first startup.');
      print('');
      print('Current environment variables:');
      print(
          '  REPUB_STORAGE_PATH: ${Platform.environment['REPUB_STORAGE_PATH'] ?? '(not set)'}');
      print(
          '  REPUB_CACHE_PATH: ${Platform.environment['REPUB_CACHE_PATH'] ?? '(not set)'}');
      print(
          '  REPUB_S3_ENDPOINT: ${Platform.environment['REPUB_S3_ENDPOINT'] ?? '(not set)'}');
      print(
          '  REPUB_S3_BUCKET: ${Platform.environment['REPUB_S3_BUCKET'] ?? '(not set)'}');
      print(
          '  REPUB_S3_REGION: ${Platform.environment['REPUB_S3_REGION'] ?? '(not set)'}');
    } else {
      print('');
      _printStorageConfig(activeConfig);
    }

    // Show pending configuration
    print('');
    print('═══ PENDING Storage Configuration ═══');
    if (pendingConfig == null || !pendingConfig.initialized) {
      print('');
      print('No pending changes.');
      print(
          'Edit storage configuration in the Admin UI to create pending changes.');
    } else {
      print('');
      _printStorageConfig(pendingConfig);
      print('');
      print(
          '⚠️  To activate: Stop server, run `storage activate`, then restart server');
    }

    await metadata.close();
  } catch (e) {
    Logger.error('Failed to show storage config',
        component: 'cli', metadata: {'error': e.toString()});
    print('');
    print('Error: $e');
    await metadata.close();
    exit(1);
  }
}

/// Print storage configuration details.
void _printStorageConfig(StorageConfig config) {
  print('  Type: ${config.type.name}');
  print('');

  if (config.type == StorageType.local) {
    print('  Local Storage:');
    print('    Storage Path: ${config.localPath}');
    print('    Cache Path: ${config.cachePath}');
  } else {
    print('  S3 Storage:');
    print('    Endpoint: ${config.s3Endpoint}');
    print('    Region: ${config.s3Region}');
    print('    Bucket: ${config.s3Bucket}');
    print('    Access Key: ${_maskCredential(config.s3AccessKey)}');
    print('    Secret Key: ${_maskCredential(config.s3SecretKey)}');
    print('    Cache Path: ${config.cachePath}');
  }

  print('');
  final isValid = config.isValid();
  if (isValid) {
    print('  Status: ✓ Valid');
  } else {
    print('  Status: ✗ Invalid');
    print('  Errors:');
    for (final error in config.validationErrors) {
      print('    - $error');
    }
  }
}

/// Activate pending storage configuration (server must be stopped).
Future<void> _runActivate(List<String> args) async {
  Logger.init();
  final config = Config.fromEnv();

  print('Connecting to database...');
  final metadata = await MetadataStore.create(config);
  await metadata.runMigrations();

  try {
    // Get active and pending configs
    final activeConfig = await metadata.getStorageConfig(config.encryptionKey);
    final pendingConfig =
        await metadata.getPendingStorageConfig(config.encryptionKey);

    // Check if there's a pending config
    if (pendingConfig == null || !pendingConfig.initialized) {
      print('');
      print('No pending storage configuration to activate.');
      print('Edit storage configuration in the Admin UI first.');
      await metadata.close();
      exit(1);
    }

    // Show what will change
    print('');
    print('═══ Current ACTIVE Configuration ═══');
    if (activeConfig == null || !activeConfig.initialized) {
      print('  (not initialized)');
    } else {
      _printStorageConfig(activeConfig);
    }

    print('');
    print('═══ Pending Configuration (to be activated) ═══');
    _printStorageConfig(pendingConfig);

    // Warn about data migration if storage type is changing
    if (activeConfig != null && activeConfig.type != pendingConfig.type) {
      print('');
      print('⚠️  WARNING: Storage type is changing!');
      print('   You MUST migrate data after activation:');
      print('');
      if (pendingConfig.type == StorageType.s3) {
        print('   dart run repub_cli storage migrate local-to-s3');
      } else {
        print(
            '   dart run repub_cli storage migrate s3-to-local --target ${pendingConfig.localPath}');
      }
      print('');
    }

    // Confirm
    print('');
    stdout.write('Activate pending configuration? [y/N]: ');
    final input = (stdin.readLineSync() ?? '').toLowerCase();
    if (input != 'y' && input != 'yes') {
      print('Activation cancelled.');
      await metadata.close();
      exit(0);
    }

    // Activate pending configuration
    print('');
    print('Activating configuration...');
    await metadata.activatePendingStorageConfig(config.encryptionKey);

    print('✓ Storage configuration activated successfully');
    print('');
    print('Next steps:');
    print('  1. Start the server for changes to take effect');
    if (activeConfig != null && activeConfig.type != pendingConfig.type) {
      print('  2. Migrate data using the storage migrate command');
    }

    await metadata.close();
  } catch (e) {
    Logger.error('Failed to activate storage config',
        component: 'cli', metadata: {'error': e.toString()});
    print('');
    print('Error: $e');
    await metadata.close();
    exit(1);
  }
}

/// Mask credentials for display (show only last 4 characters).
String _maskCredential(String? credential) {
  if (credential == null || credential.isEmpty) {
    return '(not set)';
  }
  if (credential.length <= 4) {
    return '****';
  }
  return '${'*' * (credential.length - 4)}${credential.substring(credential.length - 4)}';
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
          Logger.error('Target path required for s3-to-local migration',
              component: 'cli');
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
        Logger.error('Invalid migration direction',
            component: 'cli', metadata: {'direction': direction});
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
    Logger.error('Migration failed',
        component: 'cli', metadata: {'error': e.message});
    print('');
    print('Error: ${e.message}');
    await metadata.close();
    exit(1);
  } catch (e) {
    Logger.error('Migration failed with unexpected error',
        component: 'cli', metadata: {'error': e.toString()});
    print('');
    print('Error: $e');
    await metadata.close();
    exit(1);
  }
}

Future<void> _runVerify(List<String> args) async {
  final includeCache = args.contains('--include-cache');
  final directionArgs = args.where((a) => !a.startsWith('--')).toList();

  final targetIndex = args.indexOf('--target');
  String? targetPath;
  if (targetIndex != -1 && targetIndex + 1 < args.length) {
    targetPath = args[targetIndex + 1];
    directionArgs.remove(targetPath);
  }

  if (directionArgs.isEmpty) {
    Logger.error('Missing migration direction for verification',
        component: 'cli');
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
          Logger.error('Target path required for s3-to-local verification',
              component: 'cli');
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
        Logger.error('Invalid verification direction',
            component: 'cli', metadata: {'direction': direction});
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
    Logger.error('Verification failed',
        component: 'cli', metadata: {'error': e.message});
    print('');
    print('Error: ${e.message}');
    await metadata.close();
    exit(1);
  } catch (e) {
    Logger.error('Verification failed with unexpected error',
        component: 'cli', metadata: {'error': e.toString()});
    print('');
    print('Error: $e');
    await metadata.close();
    exit(1);
  }
}
