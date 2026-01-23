import 'dart:io';

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
  print('Database: ${cfg.databaseType.name}');
  if (cfg.enableUpstreamProxy) {
    print('Upstream proxy: ${cfg.upstreamUrl}');
  } else {
    print('Upstream proxy: disabled');
  }

  // Create metadata store (handles connection and migrations)
  print('Connecting to database...');
  final metadata = await MetadataStore.create(cfg);

  // Run migrations
  print('Running migrations...');
  final migrated = await metadata.runMigrations();
  if (migrated > 0) {
    print('Applied $migrated migration(s)');
  }

  // Create blob storage for local packages
  final blobs = BlobStore.fromConfig(cfg);

  // Create blob storage for cached upstream packages
  final cacheBlobs = BlobStore.cacheFromConfig(cfg);

  // Ensure storage is ready
  print('Checking storage...');
  await blobs.ensureReady();
  await cacheBlobs.ensureReady();

  // Create router
  final router = createRouter(
    config: cfg,
    metadata: metadata,
    blobs: blobs,
    cacheBlobs: cacheBlobs,
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
    await metadata.close();
    exit(0);
  });
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
