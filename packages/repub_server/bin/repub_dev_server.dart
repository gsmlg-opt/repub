#!/usr/bin/env dart

import 'dart:io';

import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_proxy/shelf_proxy.dart';

import 'package:repub_server/src/handlers.dart';

/// Development server that unifies API and web UI on a single port.
///
/// This server runs on port 8080 and:
/// - Handles all API routes directly (same as production)
/// - Proxies web UI requests to webdev server on port 8081 (for hot reload)
Future<void> main(List<String> args) async {
  final cfg = Config.fromEnv();

  print('Starting Repub Development Server...');
  print('Unified URL: http://localhost:8080');
  print('Database: ${cfg.databaseType.name}');

  // Create metadata store
  print('Connecting to database...');
  final metadata = await MetadataStore.create(cfg);

  // Run migrations
  print('Running migrations...');
  final migrated = await metadata.runMigrations();
  if (migrated > 0) {
    print('Applied $migrated migration(s)');
  }

  // Create blob storage
  final blobs = BlobStore.fromConfig(cfg);
  await blobs.ensureReady();

  // Create API router
  final apiRouter = createRouter(
    config: cfg,
    metadata: metadata,
    blobs: blobs,
  );

  // Create proxy handler for web dev server
  final webdevProxy = proxyHandler('http://localhost:8081');

  // Check if path looks like a static asset
  bool isAssetPath(String path) {
    return path.endsWith('.js') ||
        path.endsWith('.css') ||
        path.endsWith('.map') ||
        path.endsWith('.wasm') ||
        path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.gif') ||
        path.endsWith('.svg') ||
        path.endsWith('.ico') ||
        path.endsWith('.woff') ||
        path.endsWith('.woff2') ||
        path.endsWith('.ttf') ||
        path.endsWith('.eot');
  }

  // Combined handler: API routes first, then proxy to webdev
  Future<Response> combinedHandler(Request request) async {
    final path = request.url.path;

    // API routes - handle directly
    // /api/* - API endpoints
    // /packages/<name>/versions/<version>.tar.gz - Package downloads
    // /health - Health check
    if (path.startsWith('api/') || path == 'health') {
      return await apiRouter(request);
    }

    // Package download route: /packages/<name>/versions/<version>.tar.gz
    if (path.startsWith('packages/') && path.contains('/versions/')) {
      return await apiRouter(request);
    }

    // Everything else - proxy to webdev
    final response = await webdevProxy(request);

    // SPA fallback: if webdev returns 404 for a non-asset route,
    // serve index.html instead (for client-side routing)
    if (response.statusCode == 404 && !isAssetPath(path)) {
      // Request index.html from webdev
      final indexUri = request.requestedUri.replace(path: '/', query: '');
      final indexReq = Request('GET', indexUri,
          context: request.context, headers: request.headers);
      return await webdevProxy(indexReq);
    }

    return response;
  }

  // Add middleware
  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(combinedHandler);

  // Start unified server on port 8080
  final server = await shelf_io.serve(
    handler,
    cfg.listenAddr,
    cfg.listenPort,
  );

  print('\n🚀 Development server ready!');
  print('   Access everything at: http://localhost:8080');
  print('   API endpoints: http://localhost:8080/api/*');
  print('   Web UI: http://localhost:8080/ (with hot reload)');
  print('\nPress Ctrl+C to stop');

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
