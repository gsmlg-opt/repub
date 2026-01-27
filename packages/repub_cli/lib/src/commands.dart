import 'package:repub_model/repub_model.dart';
import 'package:repub_server/repub_server.dart';
import 'package:repub_storage/repub_storage.dart';

import 'admin_commands.dart';
import 'backup_commands.dart';
import 'storage_commands.dart';

/// Print usage information.
void printUsage() {
  print('''
Repub - Self-hosted Dart/Flutter package registry

Usage:
  dart run repub_cli <command> [options]

Commands:
  serve           Start the HTTP server
  migrate         Run database migrations
  admin <cmd>     Admin user management (create, list, reset-password, etc.)
  backup <cmd>    Database backup and restore (export, import)
  storage <cmd>   Storage migration (local <-> S3)
  help            Show this help message

Note:
  - User tokens are managed via the web UI at /account/tokens
  - Admin users are managed exclusively via CLI for security

Environment Variables:
  REPUB_LISTEN_ADDR          Listen address (default: 0.0.0.0:4920)
  REPUB_BASE_URL             Base URL for the registry
  REPUB_DATABASE_URL         Database URL (SQLite path or PostgreSQL URL)
                             Default: sqlite:./data/repub.db
                             PostgreSQL: postgres://user:pass@host:5432/db
  REPUB_STORAGE_PATH         Local storage path (optional, uses S3 if not set)
  REPUB_S3_ENDPOINT          S3/MinIO endpoint
  REPUB_S3_REGION            S3 region (default: us-east-1)
  REPUB_S3_ACCESS_KEY        S3 access key
  REPUB_S3_SECRET_KEY        S3 secret key
  REPUB_S3_BUCKET            S3 bucket name
  REPUB_REQUIRE_DOWNLOAD_AUTH  Require auth for downloads (default: false)
  REPUB_SIGNED_URL_TTL_SECONDS  Signed URL TTL (default: 3600)
''');
}

/// Run the serve command.
Future<void> runServe(List<String> args) async {
  await startServer();
}

/// Run database migrations.
Future<void> runMigrate() async {
  final config = Config.fromEnv();

  print('Database type: ${config.databaseType.name}');
  print('Connecting to database...');
  final metadata = await MetadataStore.create(config);

  print('Running migrations...');
  final count = await metadata.runMigrations();

  if (count == 0) {
    print('No pending migrations');
  } else {
    print('Applied $count migration(s)');
  }

  await metadata.close();
}

/// Handle admin commands.
Future<void> runAdminCommand(List<String> args) async {
  final config = Config.fromEnv();

  // Ensure migrations are run
  final metadata = await MetadataStore.create(config);
  await metadata.runMigrations();
  await metadata.close();

  // Run admin commands
  await adminCommands(args, config);
}

/// Handle backup commands.
Future<void> runBackupCommand(List<String> args) async {
  await backupCommands(args);
}

/// Handle storage commands.
Future<void> runStorageCommand(List<String> args) async {
  await storageCommands(args);
}
