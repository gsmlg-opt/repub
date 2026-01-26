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

  // Create blob storage for local packages
  final blobs = BlobStore.fromConfig(cfg);
  await blobs.ensureReady();

  // Create blob storage for cached upstream packages
  final cacheBlobs = BlobStore.cacheFromConfig(cfg);
  await cacheBlobs.ensureReady();

  // Create API router (disable static files - use webdev proxy instead)
  final apiRouter = createRouter(
    config: cfg,
    metadata: metadata,
    blobs: blobs,
    cacheBlobs: cacheBlobs,
    serveStaticFiles: false,
  );

  // Create proxy handlers for web dev servers
  final webdevProxy = proxyHandler('http://localhost:8081'); // Jaspr web UI
  final adminProxy = proxyHandler('http://localhost:8082'); // Flutter admin

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

  // Combined handler: API routes first, then proxy to appropriate dev server
  Future<Response> combinedHandler(Request request) async {
    final path = request.url.path;

    try {
      // API routes - handle directly
      // /api/* - API endpoints
      // /admin/api/* - Admin API endpoints
      // /packages/<name>/versions/<version>.tar.gz - Package downloads
      // /health - Health check
      if (path.startsWith('api/') ||
          path.startsWith('admin/api/') ||
          path == 'health') {
        return await apiRouter(request);
      }

      // Package download route: /packages/<name>/versions/<version>.tar.gz
      if (path.startsWith('packages/') && path.contains('/versions/')) {
        return await apiRouter(request);
      }

      // Admin routes - proxy to Flutter admin on port 8082
      // In dev mode, Flutter runs with base href "/" so we need to rewrite the HTML
      if (path.startsWith('admin')) {
        // Strip /admin prefix: /admin -> /, /admin/packages/local -> /packages/local
        final strippedPath =
            path == 'admin' ? '/' : path.substring(5); // Remove 'admin'
        final newUri = request.requestedUri.replace(path: strippedPath);
        final newRequest = Request(
          request.method,
          newUri,
          context: request.context,
          headers: request.headers,
        );

        var response = await adminProxy(newRequest);

        // SPA fallback: Flutter dev server returns 500 for client-side routes
        // If we get an error and it's not an asset, serve index.html instead
        if (response.statusCode >= 400 && !isAssetPath(strippedPath)) {
          // Request index.html from Flutter dev server
          final indexUri = request.requestedUri.replace(path: '/', query: '');
          final indexReq = Request('GET', indexUri,
              context: request.context, headers: request.headers);
          response = await adminProxy(indexReq);
        }

        // Rewrite base href in HTML for Flutter admin
        // This is needed for all HTML responses because Flutter dev server runs with <base href="/">
        // but we need <base href="/admin/"> for assets to load correctly
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('text/html') && response.statusCode == 200) {
          final body = await response.readAsString();
          // Replace <base href="/"> with <base href="/admin/">
          final rewritten = body.replaceFirst(
            '<base href="/">',
            '<base href="/admin/">',
          );
          return response.change(body: rewritten);
        }

        return response;
      }

      // Webdev SSE handler - proxy to webdev for hot reload
      if (path.startsWith(r'$dwdsSseHandler') ||
          path.startsWith(r'$requireDigestsPath')) {
        return await webdevProxy(request);
      }

      // Everything else - proxy to Jaspr webdev on port 8081
      var response = await webdevProxy(request);

      // Inject script to fix hot reload when accessing from remote IP
      // This patches EventSource to redirect localhost:8081 to current origin
      if ((path == '' || path == '/' || path == 'index.html') &&
          response.statusCode == 200) {
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('text/html')) {
          final body = await response.readAsString();
          const patchScript = '''
<script>
// Patch EventSource to redirect webdev hot reload to current origin
(function() {
  const OriginalEventSource = window.EventSource;
  window.EventSource = function(url, config) {
    if (url && url.includes('localhost:8081')) {
      url = url.replace('http://localhost:8081', location.origin);
    }
    return new OriginalEventSource(url, config);
  };
  window.EventSource.prototype = OriginalEventSource.prototype;
})();
</script>
''';

          // Inject the auto-run script at the end of body (after defer scripts have registered)
          const autoRunScript = '''
<script>
// Auto-run Dart main function after modules are loaded
// This fixes an issue where defer scripts don't auto-execute through the proxy
(function() {
  function tryRunMain() {
    // Check if require.js is loaded
    if (typeof require !== 'undefined' && require.s && require.s.contexts) {
      var app = document.querySelector('#app');
      // Check if main module is defined but app hasn't rendered
      if (app && !app.hasChildNodes()) {
        // Check if main is already defined
        var ctx = require.s.contexts._;
        if (ctx.defined && ctx.defined['web/main']) {
          // Main module is loaded, trigger it via \$dartRunMain
          if (window.\$dartRunMain) {
            window.\$dartRunMain();
            return true;
          }
        } else {
          // Main module not loaded yet, manually trigger require
          try {
            require(['web/main']);
            return true;
          } catch (e) {
            // Module not ready yet
          }
        }
      }
    }
    return false;
  }

  // Set up interval checking
  var attempts = 0;
  var checkInterval = setInterval(function() {
    attempts++;
    if (tryRunMain() || attempts > 200) {  // Stop after 10 seconds (200 * 50ms)
      clearInterval(checkInterval);
    }
  }, 50);
})();
</script>
''';

          // Fix defer attribute issue: remove defer from main.dart.js to ensure it executes
          var patched = body.replaceAll('<script defer src="main.dart.js">',
              '<script src="main.dart.js">');

          // Inject patch script before </head> and auto-run script before </body>
          patched = patched.replaceFirst('</head>', '$patchScript</head>');
          patched = patched.replaceFirst('</body>', '$autoRunScript</body>');
          response = response.change(body: patched);
        }
      }

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
    } catch (e, stack) {
      // Check if it's a connection refused to dev servers (expected during startup)
      final errorStr = e.toString();
      if (errorStr.contains('Connection refused') &&
          (errorStr.contains('8081') || errorStr.contains('8082'))) {
        // Dev server not ready yet - return a friendly message without stack trace
        return Response(
          503,
          body: 'Dev servers starting... Please refresh in a moment.',
          headers: {'content-type': 'text/plain', 'retry-after': '2'},
        );
      }

      // Log other errors with full stack trace
      print('\x1B[31m[ERROR]\x1B[0m ${request.method} /${request.url.path}');
      print('\x1B[31m$e\x1B[0m');
      print('\x1B[33m$stack\x1B[0m');
      return Response.internalServerError(body: 'Internal Server Error: $e');
    }
  }

  // Add middleware with custom access logging
  final handler = const Pipeline()
      .addMiddleware(_accessLogMiddleware())
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
  print('   Web UI: http://localhost:8080/ (Jaspr, with hot reload)');
  print('   Admin UI: http://localhost:8080/admin (Flutter, with hot reload)');
  print('\nPress Ctrl+C to stop');

  // Handle shutdown
  ProcessSignal.sigint.watch().listen((_) async {
    print('\nShutting down...');
    await server.close();
    await metadata.close();
    exit(0);
  });
}

/// Access log middleware with colored output.
Middleware _accessLogMiddleware() {
  return (Handler innerHandler) {
    return (Request request) async {
      final stopwatch = Stopwatch()..start();

      Response response;
      try {
        response = await innerHandler(request);
      } catch (e) {
        // Don't log here - let the error handler in combinedHandler do it
        rethrow;
      }

      stopwatch.stop();

      final status = response.statusCode;

      // Skip logging 500 errors - those are already logged with stack trace
      if (status >= 500) {
        return response;
      }

      final method = request.method.padRight(6);
      final path = '/${request.url.path}';
      final duration = '${stopwatch.elapsedMilliseconds}ms'.padLeft(6);

      // Color code based on status
      String statusColor;
      if (status >= 400) {
        statusColor = '\x1B[33m'; // Yellow
      } else if (status >= 300) {
        statusColor = '\x1B[36m'; // Cyan
      } else {
        statusColor = '\x1B[32m'; // Green
      }
      const reset = '\x1B[0m';

      stdout.writeln('$statusColor$status$reset $method $path $duration');

      return response;
    };
  };
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
