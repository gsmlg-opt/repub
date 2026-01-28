import 'dart:io';

import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';

/// Handle backup sub-commands.
Future<void> backupCommands(List<String> args) async {
  if (args.isEmpty) {
    _printBackupUsage();
    exit(1);
  }

  final command = args.first;
  final subArgs = args.length > 1 ? args.sublist(1) : <String>[];

  switch (command) {
    case 'export':
      await _exportBackup(subArgs);
    case 'import':
      await _importBackup(subArgs);
    case 'help':
    case '--help':
    case '-h':
      _printBackupUsage();
    default:
      Logger.error('Unknown backup command', component: 'cli', metadata: {'command': command});
      print('Unknown backup command: $command');
      _printBackupUsage();
      exit(1);
  }
}

void _printBackupUsage() {
  print('''
Database Backup Commands

Usage:
  dart run repub_cli backup <command> [options]

Commands:
  export <file>   Export database to JSON file
  import <file>   Import database from JSON file
  help            Show this help message

Examples:
  # Export database to backup file
  dart run repub_cli backup export backup-2026-01-28.json

  # Import database from backup file
  dart run repub_cli backup import backup-2026-01-28.json

  # Preview import without making changes
  dart run repub_cli backup import --dry-run backup-2026-01-28.json

Options for import:
  --dry-run       Preview changes without importing
  --force         Skip confirmation prompt

Note:
  - Backups include database tables only (packages, users, tokens, etc.)
  - Blob storage (package archives) must be backed up separately
  - For local storage: copy the storage directory
  - For S3: use S3 bucket replication or aws s3 sync
''');
}

Future<void> _exportBackup(List<String> args) async {
  if (args.isEmpty) {
    Logger.error('Missing output file path for backup export', component: 'cli');
    print('Error: Missing output file path');
    print('Usage: dart run repub_cli backup export <file>');
    exit(1);
  }

  final filePath = args.first;
  final config = Config.fromEnv();

  print('Database: ${config.databaseType.name}');
  print('Connecting to database...');

  final metadata = await MetadataStore.create(config);
  await metadata.runMigrations();

  print('Creating backup...');
  final backupManager = BackupManager(metadata);

  try {
    await backupManager.exportToFile(filePath);
    print('');
    print('Backup exported successfully to: $filePath');

    // Show summary
    final backup = await backupManager.createBackup();
    print('');
    print('Summary:');
    backup.summary.forEach((key, value) {
      print('  $key: $value');
    });
  } catch (e) {
    Logger.error('Failed to create backup', component: 'cli', metadata: {'error': e.toString()});
    print('Error creating backup: $e');
    exit(1);
  } finally {
    await metadata.close();
  }
}

Future<void> _importBackup(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final force = args.contains('--force');
  final fileArgs = args.where((a) => !a.startsWith('--')).toList();

  if (fileArgs.isEmpty) {
    Logger.error('Missing input file path for backup import', component: 'cli');
    print('Error: Missing input file path');
    print(
        'Usage: dart run repub_cli backup import [--dry-run] [--force] <file>');
    exit(1);
  }

  final filePath = fileArgs.first;
  final file = File(filePath);

  if (!file.existsSync()) {
    Logger.error('Backup file not found', component: 'cli', metadata: {'file': filePath});
    print('Error: Backup file not found: $filePath');
    exit(1);
  }

  final config = Config.fromEnv();

  print('Database: ${config.databaseType.name}');
  print('Connecting to database...');

  final metadata = await MetadataStore.create(config);
  await metadata.runMigrations();

  final backupManager = BackupManager(metadata);

  try {
    // Preview the import
    print('');
    print('Backup file: $filePath');
    final summary = await backupManager.importFromFile(filePath, dryRun: true);

    print('');
    print('Records to import:');
    summary.forEach((key, value) {
      print('  $key: $value');
    });

    if (dryRun) {
      print('');
      print('Dry run complete. No changes were made.');
      return;
    }

    // Confirm import
    if (!force) {
      print('');
      print('WARNING: This will overwrite existing records with matching IDs.');
      stdout.write('Continue with import? [y/N]: ');
      final input = (stdin.readLineSync() ?? '').toLowerCase();

      if (input != 'y' && input != 'yes') {
        print('Import cancelled.');
        exit(0);
      }
    }

    // Perform import
    print('');
    print('Importing...');
    await backupManager.importFromFile(filePath);

    print('');
    print('Import completed successfully!');
  } on BackupException catch (e) {
    Logger.error('Backup import failed', component: 'cli', metadata: {'error': e.message});
    print('');
    print('Error: ${e.message}');
    exit(1);
  } catch (e) {
    Logger.error('Backup import failed with unexpected error', component: 'cli', metadata: {'error': e.toString()});
    print('');
    print('Error importing backup: $e');
    exit(1);
  } finally {
    await metadata.close();
  }
}
