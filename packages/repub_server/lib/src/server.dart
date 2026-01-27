import 'dart:io';

import 'package:repub_auth/repub_auth.dart';
import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'handlers.dart';
import 'logger.dart';
import 'rate_limit.dart';

/// Start the repub server.
Future<void> startServer({Config? config}) async {
  // Initialize logger from environment
  Logger.init();

  final cfg = config ?? Config.fromEnv();

  Logger.info('Starting Repub server...', component: 'startup');
  Logger.info('Configuration loaded', component: 'startup', metadata: {
    'baseUrl': cfg.baseUrl,
    'database': cfg.databaseType.name,
    'upstreamProxy': cfg.enableUpstreamProxy,
    'upstreamUrl': cfg.enableUpstreamProxy ? cfg.upstreamUrl : null,
    'rateLimit': '${cfg.rateLimitRequests}/${cfg.rateLimitWindowSeconds}s',
  });

  // Create metadata store (handles connection and migrations)
  Logger.info('Connecting to database...', component: 'database');
  final metadata = await MetadataStore.create(cfg);

  // Run migrations
  Logger.info('Running migrations...', component: 'database');
  final migrated = await metadata.runMigrations();
  if (migrated > 0) {
    Logger.info('Applied migrations', component: 'database', metadata: {'count': migrated});
  }

  // Ensure default admin user exists
  final createdAdmin = await metadata.ensureDefaultAdminUser(hashPassword);
  if (createdAdmin) {
    Logger.warn('Created default admin user', component: 'security', metadata: {
      'username': 'admin',
      'action': 'Please change the password on first login!',
    });
  }

  // Create blob storage for local packages
  final blobs = BlobStore.fromConfig(cfg);

  // Create blob storage for cached upstream packages
  final cacheBlobs = BlobStore.cacheFromConfig(cfg);

  // Ensure storage is ready
  Logger.info('Checking storage...', component: 'storage');
  await blobs.ensureReady();
  await cacheBlobs.ensureReady();

  // Create router
  final router = createRouter(
    config: cfg,
    metadata: metadata,
    blobs: blobs,
    cacheBlobs: cacheBlobs,
  );

  // Add middleware pipeline
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addMiddleware(_versionMiddleware())
      .addMiddleware(rateLimitMiddleware(
        keyExtractor: extractCompositeKey,
        config: RateLimitConfig(
          maxRequests: cfg.rateLimitRequests,
          windowSeconds: cfg.rateLimitWindowSeconds,
        ),
        excludePaths: ['health', 'metrics'],
      ))
      .addHandler(router.call);

  // Start server
  final server = await shelf_io.serve(
    handler,
    cfg.listenAddr,
    cfg.listenPort,
  );

  Logger.info('Server started', component: 'startup', metadata: {
    'address': 'http://${server.address.host}:${server.port}',
  });
  Logger.info('Press Ctrl+C to stop', component: 'startup');

  // Handle shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    Logger.info('Shutting down...', component: 'shutdown');
    await server.close();
    await metadata.close();
    Logger.info('Server stopped', component: 'shutdown');
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

/// Version middleware to inject version info in response headers.
Middleware _versionMiddleware() {
  final version = Platform.environment['REPUB_VERSION'] ?? 'unknown';
  final gitHash = Platform.environment['REPUB_GIT_HASH'] ?? 'unknown';

  return (Handler innerHandler) {
    return (Request request) async {
      final response = await innerHandler(request);
      return response.change(headers: {
        'X-Repub-Version': version,
        'X-Repub-Git-Hash': gitHash,
      });
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
};
