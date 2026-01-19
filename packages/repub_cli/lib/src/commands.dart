import 'dart:io';

import 'package:repub_migrate/repub_migrate.dart';
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
  REPUB_DATABASE_URL         PostgreSQL connection URL
  REPUB_S3_ENDPOINT          S3/MinIO endpoint
  REPUB_S3_REGION            S3 region (default: us-east-1)
  REPUB_S3_ACCESS_KEY        S3 access key
  REPUB_S3_SECRET_KEY        S3 secret key
  REPUB_S3_BUCKET            S3 bucket name (default: repub)
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

  print('Connecting to database...');
  final conn = await connectDb(config);

  print('Running migrations...');
  final count = await runMigrations(conn);

  if (count == 0) {
    print('No pending migrations');
  } else {
    print('Applied $count migration(s)');
  }

  await conn.close();
}

/// Handle token commands.
Future<void> runTokenCommand(List<String> args) async {
  if (args.isEmpty) {
    print('Usage:');
    print('  dart run repub_cli token create <label> [scopes...]');
    print('  dart run repub_cli token list');
    print('  dart run repub_cli token delete <label>');
    print('');
    print('Scopes:');
    print('  admin         - Full access');
    print('  publish:all   - Publish any package');
    print('  publish:pkg:NAME - Publish specific package');
    print('  read:all      - Read/download packages (needed if REQUIRE_DOWNLOAD_AUTH=true)');
    exit(1);
  }

  final config = Config.fromEnv();
  final conn = await connectDb(config);
  final metadata = MetadataStore(conn);

  try {
    switch (args[0]) {
      case 'create':
        if (args.length < 2) {
          print('Usage: dart run repub_cli token create <label> [scopes...]');
          print('Example: dart run repub_cli token create ci-publish publish:all');
          exit(1);
        }
        final label = args[1];
        final scopes = args.length > 2 ? args.sublist(2) : ['publish:all'];

        final token = await metadata.createToken(label: label, scopes: scopes);
        print('Created token: $token');
        print('');
        print('Use this token with:');
        print('  dart pub token add ${config.baseUrl}');
        print('  (paste the token when prompted)');

      case 'list':
        final tokens = await metadata.listTokens();
        if (tokens.isEmpty) {
          print('No tokens found');
        } else {
          print('Tokens:');
          for (final t in tokens) {
            print('  ${t['label']}');
            print('    Scopes: ${(t['scopes'] as List).join(', ')}');
            print('    Created: ${t['created_at']}');
            print('    Last used: ${t['last_used_at'] ?? 'never'}');
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
    await conn.close();
  }
}
