import 'dart:io';

import 'package:repub_model/repub_model.dart';
import 'package:repub_server/repub_server.dart';
import 'package:repub_storage/repub_storage.dart';

/// Print usage information.
void printUsage() {
  print('''
Repub - Self-hosted Dart/Flutter package registry

Usage:
  dart run repub_cli <command> [options]

Commands:
  serve           Start the HTTP server
  migrate         Run database migrations
  token create    Create a new auth token
  token list      List all tokens
  token delete    Delete a token
  help            Show this help message

Environment Variables:
  REPUB_LISTEN_ADDR          Listen address (default: 0.0.0.0:8080)
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

/// Handle token commands.
Future<void> runTokenCommand(List<String> args) async {
  if (args.isEmpty) {
    print('Usage:');
    print('  dart run repub_cli token create <label> [user_id]');
    print('  dart run repub_cli token list [user_id]');
    print('  dart run repub_cli token delete <label>');
    print('');
    print('Notes:');
    print('  - Tokens authenticate users for publishing');
    print('  - If user_id is not specified, anonymous user is used');
    print('  - Users can only publish to packages they own');
    print('  - First publisher of a package becomes its owner');
    exit(1);
  }

  final config = Config.fromEnv();
  final metadata = await MetadataStore.create(config);

  // Ensure migrations are run
  await metadata.runMigrations();

  try {
    switch (args[0]) {
      case 'create':
        if (args.length < 2) {
          print('Usage: dart run repub_cli token create <label> [user_id]');
          print('Example: dart run repub_cli token create ci-publish');
          print('Example: dart run repub_cli token create my-token user-uuid');
          exit(1);
        }
        final label = args[1];
        final userId = args.length > 2 ? args[2] : User.anonymousId;

        final token = await metadata.createToken(label: label, userId: userId);
        print('Created token: $token');
        print('');
        print('Use this token with:');
        print('  dart pub token add ${config.baseUrl}');
        print('  (paste the token when prompted)');

      case 'list':
        final userId = args.length > 1 ? args[1] : null;
        final tokens = await metadata.listTokens(userId: userId);
        if (tokens.isEmpty) {
          print('No tokens found');
        } else {
          print('Tokens:');
          for (final t in tokens) {
            print('  ${t.label}');
            print('    User: ${t.userId}');
            print('    Created: ${t.createdAt}');
            print('    Last used: ${t.lastUsedAt ?? 'never'}');
            if (t.expiresAt != null) {
              print('    Expires: ${t.expiresAt}');
            }
          }
        }

      case 'delete':
        if (args.length < 2) {
          print('Usage: dart run repub_cli token delete <label>');
          exit(1);
        }
        final label = args[1];
        final deleted = await metadata.deleteToken(label);
        if (deleted) {
          print('Deleted token: $label');
        } else {
          print('Token not found: $label');
          exit(1);
        }

      default:
        print('Unknown token command: ${args[0]}');
        exit(1);
    }
  } finally {
    await metadata.close();
  }
}
