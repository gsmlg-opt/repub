import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:repub_migrate/repub_migrate.dart';
import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'handlers.dart';

/// Start the repub server.
Future<void> startServer({Config? config}) async {
  final cfg = config ?? Config.fromEnv();

  print('Starting Repub server...');
  print('Base URL: ${cfg.baseUrl}');

  // Connect to database
  print('Connecting to database...');
  final conn = await connectDb(cfg);

  // Run migrations
  print('Running migrations...');
  final migrated = await runMigrations(conn);
  if (migrated > 0) {
    print('Applied $migrated migration(s)');
  }

  // Create storage
  final metadata = MetadataStore(conn);
  final blobs = BlobStore.fromConfig(cfg);

  // Ensure storage is ready
  print('Checking storage...');
  await blobs.ensureReady();

  // Create router
  final router = createRouter(
    config: cfg,
    metadata: metadata,
    blobs: blobs,
  );

  // Add logging middleware
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(router.call);

  // Start server
  final server = await shelf_io.serve(
    handler,
    cfg.listenAddr,
    cfg.listenPort,
  );

  print(
      'Repub server listening on http://${server.address.host}:${server.port}');
  print('Press Ctrl+C to stop');

  // Handle shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nShutting down...');
    await server.close();
    await conn.close();
    exit(0);
  });
}

/// Connect to the database with retries.
Future<Connection> connectDb(Config config) async {
  final uri = Uri.parse(config.databaseUrl);
  final userInfo = uri.userInfo.split(':');

  final endpoint = Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'repub',
    username: userInfo.isNotEmpty ? userInfo[0] : 'repub',
    password: userInfo.length > 1 ? userInfo[1] : 'repub',
  );

  // Keep trying to connect for up to 30 seconds
  for (var i = 0; i < 30; i++) {
    try {
      return await Connection.open(
        endpoint,
        settings: ConnectionSettings(sslMode: SslMode.disable),
      );
    } catch (e) {
      if (i == 29) rethrow;
      print('Waiting for database... (${i + 1}/30)');
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  throw StateError('Could not connect to database');
}

/// CORS middleware for development.
Middleware _corsMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }

      final response = await innerHandler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
};
