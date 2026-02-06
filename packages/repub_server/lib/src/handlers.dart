import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:repub_auth/repub_auth.dart';
import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'csv_export.dart';
import 'email_service.dart';
import 'feed.dart';
import 'password_crypto.dart';
import 'publish.dart';
import 'upstream.dart';
import 'webhook_service.dart';

/// Create the API router.
/// Set [serveStaticFiles] to false in dev mode to use webdev proxy instead.
Router createRouter({
  required Config config,
  required MetadataStore metadata,
  required BlobStore blobs,
  required BlobStore cacheBlobs,
  required PasswordCrypto passwordCrypto,
  bool serveStaticFiles = true,
}) {
  final router = Router();
  final handlers = ApiHandlers(
      config: config,
      metadata: metadata,
      blobs: blobs,
      cacheBlobs: cacheBlobs,
      passwordCrypto: passwordCrypto);

  // List all packages (for web UI)
  router.get('/api/packages', handlers.listPackages);

  // Search packages (for web UI)
  router.get('/api/packages/search', handlers.searchPackages);
  router.get('/api/packages/search/upstream', handlers.searchPackagesUpstream);

  // Upstream package info endpoint
  router.get('/api/upstream/packages/<name>', handlers.getUpstreamPackage);

  // Package info endpoint
  router.get('/api/packages/<name>', handlers.getPackage);

  // Version info endpoint
  router.get('/api/packages/<name>/versions/<version>', handlers.getVersion);

  // Publish flow
  router.get('/api/packages/versions/new', handlers.initiateUpload);
  router.post(
      '/api/packages/versions/upload/<sessionId>', handlers.uploadPackage);
  router.get(
      '/api/packages/versions/finalize/<sessionId>', handlers.finalizeUpload);

  // Download endpoint (legacy format)
  router.get(
      '/packages/<name>/versions/<version>.tar.gz', handlers.downloadPackage);

  // RSS/Atom feeds - global (all recent package updates)
  router.get('/feed.rss', handlers.globalRssFeed);
  router.get('/feed.atom', handlers.globalAtomFeed);

  // RSS/Atom feeds - per package
  router.get('/packages/<name>/feed.rss', handlers.packageRssFeed);
  router.get('/packages/<name>/feed.atom', handlers.packageAtomFeed);

  // Health check - basic (for load balancer probes)
  router.get('/health', (Request req) {
    return Response.ok(jsonEncode({'status': 'ok'}),
        headers: {'content-type': 'application/json'});
  });

  // Health check - detailed (includes database status)
  router.get('/health/detailed', handlers.detailedHealthCheck);

  // Prometheus metrics endpoint
  router.get('/metrics', handlers.prometheusMetrics);

  // Version info
  router.get('/api/version', (Request req) {
    final version = Platform.environment['REPUB_VERSION'] ?? 'unknown';
    final gitHash = Platform.environment['REPUB_GIT_HASH'] ?? 'unknown';
    return Response.ok(
      jsonEncode({
        'version': version,
        'gitHash': gitHash,
      }),
      headers: {'content-type': 'application/json'},
    );
  });

  // Admin authentication endpoints (public)
  router.post('/admin/api/auth/login', handlers.adminLogin);
  router.post('/admin/api/auth/logout', handlers.adminLogout);
  router.get('/admin/api/auth/me', handlers.adminMe);
  router.post('/admin/api/auth/change-password', handlers.adminChangePassword);

  // Admin user management endpoints
  router.get('/admin/api/admin-users', handlers.adminListAdminUsers);
  router.get('/admin/api/admin-users/<id>', handlers.adminGetAdminUser);
  router.get('/admin/api/admin-users/<id>/login-history',
      handlers.adminGetLoginHistory);

  // Admin endpoints (protected - each handler verifies admin session)
  router.get('/admin/api/stats', handlers.adminGetStats);
  router.get('/admin/api/analytics/packages-created',
      handlers.adminGetPackagesCreatedPerDay);
  router.get(
      '/admin/api/analytics/downloads', handlers.adminGetDownloadsPerHour);
  router.get('/admin/api/activity', handlers.adminGetRecentActivity);
  router.get('/admin/api/export/packages', handlers.adminExportPackagesCsv);
  router.get('/admin/api/export/activity', handlers.adminExportActivityCsv);
  router.get('/admin/api/export/downloads', handlers.adminExportDownloadsCsv);
  router.get('/admin/api/hosted-packages', handlers.adminListHostedPackages);
  router.get('/admin/api/cached-packages', handlers.adminListCachedPackages);
  router.get('/admin/api/packages/<name>/stats', handlers.adminGetPackageStats);
  router.get(
      '/admin/api/packages/<name>/versions', handlers.adminGetPackageVersions);
  router.delete('/admin/api/packages/<name>', handlers.adminDeletePackage);
  router.delete('/admin/api/packages/<name>/versions/<version>',
      handlers.adminDeletePackageVersion);
  router.post('/admin/api/packages/<name>/versions/<version>/retract',
      handlers.adminRetractPackageVersion);
  router.delete('/admin/api/packages/<name>/versions/<version>/retract',
      handlers.adminUnretractPackageVersion);
  router.get('/admin/api/packages/<name>/dependencies',
      handlers.adminGetPackageDependencies);
  router.post('/admin/api/packages/<name>/transfer',
      handlers.adminTransferPackageOwnership);
  router.post('/admin/api/packages/<name>/discontinue',
      handlers.adminDiscontinuePackage);
  router.delete('/admin/api/cache', handlers.adminClearCache);
  // Semantic route for cached package deletion (same handler as /packages/:name)
  router.delete(
      '/admin/api/cached-packages/<name>', handlers.adminDeletePackage);
  router.get('/admin/api/users', handlers.adminListUsers);
  router.post('/admin/api/users', handlers.adminCreateUser);
  router.put('/admin/api/users/<id>', handlers.adminUpdateUser);
  router.delete('/admin/api/users/<id>', handlers.adminDeleteUser);
  router.get('/admin/api/users/<id>/tokens', handlers.adminListUserTokens);
  router.get('/admin/api/config', handlers.adminGetAllConfig);
  router.put('/admin/api/config/<name>', handlers.adminSetConfig);

  // Webhook management (admin only)
  router.get('/admin/api/webhooks', handlers.adminListWebhooks);
  router.post('/admin/api/webhooks', handlers.adminCreateWebhook);
  router.get('/admin/api/webhooks/<id>', handlers.adminGetWebhook);
  router.put('/admin/api/webhooks/<id>', handlers.adminUpdateWebhook);
  router.delete('/admin/api/webhooks/<id>', handlers.adminDeleteWebhook);
  router.get('/admin/api/webhooks/<id>/deliveries',
      handlers.adminGetWebhookDeliveries);
  router.post('/admin/api/webhooks/<id>/test', handlers.adminTestWebhook);

  // Public key endpoint (for password encryption)
  router.get('/api/public-key', handlers.getPublicKey);

  // Auth endpoints (user authentication)
  router.post('/api/auth/register', handlers.authRegister);
  router.post('/api/auth/login', handlers.authLogin);
  router.post('/api/auth/logout', handlers.authLogout);
  router.get('/api/auth/me', handlers.authMe);
  router.put('/api/auth/me', handlers.authUpdateMe);

  // Token management (session-authenticated)
  router.get('/api/tokens', handlers.listUserTokens);
  router.post('/api/tokens', handlers.createUserToken);
  router.delete('/api/tokens/<label>', handlers.deleteUserToken);

  // Admin UI static files - serve from admin build directory (skip in dev mode)
  // Note: /admin/api/* routes are already registered above
  if (serveStaticFiles) {
    final adminDir = _findAdminDir();
    if (adminDir != null) {
      final adminStaticHandler = createStaticHandler(
        adminDir,
        defaultDocument: 'index.html',
      );

      // Serve admin UI at /admin (redirect to /admin/)
      router.get('/admin', (Request req) {
        return Response.movedPermanently('/admin/');
      });

      // Serve admin UI at /admin/
      router.get('/admin/', (Request req) async {
        final indexUri = req.requestedUri.replace(path: '/index.html');
        final indexReq = Request('GET', indexUri,
            context: req.context, headers: req.headers);
        return adminStaticHandler(indexReq);
      });

      // Serve admin static assets at /admin/<path>
      router.all('/admin/<path|.*>', (Request req, String path) async {
        // Skip API routes - they're handled above
        if (path.startsWith('api/')) {
          return Response.notFound('Not found');
        }

        // Rewrite request path to strip /admin prefix for static handler
        final assetUri = req.requestedUri.replace(path: '/$path');
        final assetReq = Request(req.method, assetUri,
            context: req.context, headers: req.headers);

        // Try to serve static file
        final response = await adminStaticHandler(assetReq);
        if (response.statusCode != 404) {
          return response;
        }

        // For SPA routes, serve index.html
        final indexUri = req.requestedUri.replace(path: '/index.html');
        final indexReq = Request('GET', indexUri,
            context: req.context, headers: req.headers);
        return adminStaticHandler(indexReq);
      });
    }
  }

  // Web UI static files - serve from web build directory (skip in dev mode)
  if (serveStaticFiles) {
    final webDir = _findWebDir();
    if (webDir != null) {
      final staticHandler = createStaticHandler(
        webDir,
        defaultDocument: 'index.html',
      );

      // Serve index.html for SPA routes
      router.get('/', (Request req) => staticHandler(req));

      // Serve static assets
      router.all('/<path|.*>', (Request req, String path) async {
        // Check if it's an API route or package download route
        // Allow DDC modules at /packages/build_web_compilers/* but block
        // Dart package downloads at /packages/<name>/versions/<version>.tar.gz
        if (path.startsWith('api/') ||
            (path.startsWith('packages/') && path.contains('/versions/'))) {
          return Response.notFound('Not found');
        }

        // Try to serve static file
        final response = await staticHandler(req);
        if (response.statusCode != 404) {
          return response;
        }

        // For SPA routes, serve index.html
        // Build absolute URI from original request
        final requestedUri = req.requestedUri;
        final indexUri = requestedUri.replace(path: '/index.html', query: '');
        final indexReq = Request('GET', indexUri,
            context: req.context, headers: req.headers);
        return staticHandler(indexReq);
      });
    }
  }

  return router;
}

/// Find the web UI build directory.
String? _findWebDir() {
  // Check common locations for the web build
  final candidates = [
    // When running from workspace root
    'packages/repub_web/build/web',
    // When running from server package
    '../repub_web/build/web',
    // Docker/production location
    '/app/web',
    // Environment variable override
    Platform.environment['REPUB_WEB_DIR'],
  ];

  for (final path in candidates) {
    if (path == null) continue;
    final dir = Directory(path);
    if (dir.existsSync() && File(p.join(path, 'index.html')).existsSync()) {
      Logger.debug('Serving web UI',
          component: 'static', metadata: {'path': dir.absolute.path});
      return path;
    }
  }

  Logger.warn('Web UI not found - run "melos run build:web" to build it',
      component: 'static');
  return null;
}

/// Find the admin UI build directory.
String? _findAdminDir() {
  // Check common locations for the admin build
  final candidates = [
    // When running from workspace root
    'packages/repub_admin/build/web',
    // When running from server package
    '../repub_admin/build/web',
    // Docker/production location
    '/app/admin',
    // Environment variable override
    Platform.environment['REPUB_ADMIN_DIR'],
  ];

  for (final path in candidates) {
    if (path == null) continue;
    final dir = Directory(path);
    if (dir.existsSync() && File(p.join(path, 'index.html')).existsSync()) {
      Logger.debug('Serving admin UI',
          component: 'static', metadata: {'path': dir.absolute.path});
      return path;
    }
  }

  Logger.warn('Admin UI not found - run "melos run build:admin" to build it',
      component: 'static');
  return null;
}

/// API handler implementations.
class ApiHandlers {
  final Config config;
  final MetadataStore metadata;
  final BlobStore blobs;
  final BlobStore cacheBlobs;
  final PasswordCrypto passwordCrypto;

  // In-memory storage for upload data (sessionId -> bytes)
  final Map<String, Uint8List> _uploadData = {};

  // Track session creation times for TTL-based cleanup
  final Map<String, DateTime> _uploadSessionCreatedAt = {};

  // Upload session TTL (1 hour)
  static const _uploadSessionTtl = Duration(hours: 1);

  // Pre-compiled regex patterns for password validation (performance optimization)
  static final _uppercaseRegex = RegExp(r'[A-Z]');
  static final _lowercaseRegex = RegExp(r'[a-z]');
  static final _digitRegex = RegExp(r'[0-9]');

  // Pre-compiled email validation regex
  static final _emailRegex =
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');

  // Cleanup timer for orphaned upload sessions
  Timer? _uploadSessionCleanupTimer;

  // Upstream client for caching proxy
  UpstreamClient? _upstream;

  // Webhook service for triggering events
  WebhookService? _webhookService;

  // Email service for sending notifications
  EmailService? _emailService;

  ApiHandlers({
    required this.config,
    required this.metadata,
    required this.blobs,
    required this.cacheBlobs,
    required this.passwordCrypto,
  }) {
    // Start periodic cleanup for orphaned upload sessions (every 10 minutes)
    _uploadSessionCleanupTimer =
        Timer.periodic(const Duration(minutes: 10), (_) {
      _cleanupOrphanedUploadSessions();
    });
  }

  /// Cleanup upload sessions that have exceeded their TTL.
  void _cleanupOrphanedUploadSessions() {
    final now = DateTime.now();
    final expiredSessions = <String>[];

    for (final entry in _uploadSessionCreatedAt.entries) {
      if (now.difference(entry.value) > _uploadSessionTtl) {
        expiredSessions.add(entry.key);
      }
    }

    if (expiredSessions.isNotEmpty) {
      Logger.info(
        'Cleaning up orphaned upload sessions',
        component: 'upload',
        metadata: {'count': expiredSessions.length},
      );
      for (final sessionId in expiredSessions) {
        _uploadData.remove(sessionId);
        _uploadSessionCreatedAt.remove(sessionId);
      }
    }
  }

  /// Dispose resources (call when shutting down).
  void dispose() {
    _uploadSessionCleanupTimer?.cancel();
    _uploadSessionCleanupTimer = null;
  }

  /// Get the webhook service (lazy initialization).
  WebhookService get webhooks => _webhookService ??= WebhookService(
        metadata: metadata,
        onWebhookDisabled: _handleWebhookDisabled,
      );

  /// Get the email service (lazy initialization).
  EmailService get emails => _emailService ??= EmailService(metadata: metadata);

  /// Handle webhook disabled callback - notifies admins via email.
  void _handleWebhookDisabled(Webhook webhook, String reason) {
    // Fire-and-forget notification to avoid blocking webhook processing
    _notifyOfDisabledWebhookAsync(webhook, reason);
  }

  /// Async helper for notifying of disabled webhook.
  Future<void> _notifyOfDisabledWebhookAsync(
    Webhook webhook,
    String reason,
  ) async {
    try {
      await emails.onWebhookDisabled(
        webhookId: webhook.id,
        webhookUrl: webhook.url,
        reason: reason,
        baseUrl: config.baseUrl,
      );
    } catch (e, stack) {
      Logger.error(
        'Failed to send webhook disabled notification',
        component: 'webhook',
        error: e,
        stackTrace: stack,
      );
    }
  }

  /// Create a JSON error response with consistent format.
  ///
  /// This helper ensures all API errors follow the format:
  /// ```json
  /// {"error": {"code": "error_code", "message": "Human-readable message"}}
  /// ```
  Response _errorResponse(int statusCode, String code, String message) {
    return Response(
      statusCode,
      body: jsonEncode({
        'error': {'code': code, 'message': message},
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Create a JSON success response with the given data.
  Response _jsonResponse(Map<String, dynamic> data, {int statusCode = 200}) {
    return Response(
      statusCode,
      body: jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Extract client IP address from request headers.
  ///
  /// Checks X-Forwarded-For and X-Real-IP headers in order of precedence.
  /// Returns null if no IP can be determined.
  String? _extractClientIp(Request request) {
    // X-Forwarded-For can contain multiple IPs: "client, proxy1, proxy2"
    final forwardedFor = request.headers['x-forwarded-for'];
    if (forwardedFor != null && forwardedFor.isNotEmpty) {
      final firstIp = forwardedFor.split(',').first.trim();
      if (firstIp.isNotEmpty) {
        return firstIp;
      }
    }

    // Fall back to X-Real-IP
    final realIp = request.headers['x-real-ip'];
    if (realIp != null && realIp.isNotEmpty) {
      return realIp;
    }

    return null;
  }

  /// Trigger webhook with error logging (fire-and-forget but logged).
  void _triggerWebhook(Future<void> Function() action, String eventName) {
    action().catchError((Object error, StackTrace stack) {
      Logger.error(
        'Webhook trigger failed',
        component: 'webhook',
        metadata: {'event': eventName, 'error': error.toString()},
        stackTrace: stack,
      );
    });
  }

  /// Send email notification with error logging (fire-and-forget but logged).
  void _sendEmail(Future<void> Function() action, String emailType) {
    action().catchError((Object error, StackTrace stack) {
      Logger.error(
        'Email notification failed',
        component: 'email',
        metadata: {'type': emailType, 'error': error.toString()},
        stackTrace: stack,
      );
    });
  }

  /// Verify admin session. Returns error Response if invalid, null if valid.
  Future<Response?> _requireAdminAuth(Request request) async {
    final result = await getAdminSession(
      request,
      lookupSession: metadata.getAdminSession,
    );

    if (result is! AdminSessionValid) {
      return adminSessionErrorResponse(result);
    }

    final session = result.session;
    final adminUser = await metadata.getAdminUser(session.userId);

    if (adminUser == null || !adminUser.isActive) {
      return Response(
        401,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {
            'code': 'admin_inactive',
            'message': 'Admin user is inactive or not found'
          },
        }),
      );
    }

    return null; // Success - no error
  }

  /// Get admin user from session (for activity logging).
  Future<AdminUser?> _getAdminFromSession(Request request) async {
    final result = await getAdminSession(
      request,
      lookupSession: metadata.getAdminSession,
    );

    if (result is! AdminSessionValid) {
      return null;
    }

    final session = result.session;
    return await metadata.getAdminUser(session.userId);
  }

  /// Read the full request body as a Uint8List.
  ///
  /// This helper method collects all bytes from the request body stream
  /// into a single byte array. Use this instead of manually calling
  /// `request.read().expand((x) => x).toList()`.
  Future<Uint8List> _readRequestBody(Request request) async {
    final bytes = await request.read().expand((chunk) => chunk).toList();
    return Uint8List.fromList(bytes);
  }

  /// Validate webhook URL for SSRF protection.
  /// Returns null if valid, or error Response if invalid.
  Response? _validateWebhookUrl(String url) {
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        return Response(
          400,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'error': {
              'code': 'invalid_url',
              'message': 'URL must use HTTP or HTTPS protocol',
            },
          }),
        );
      }

      // SSRF Protection: Block private/internal IP addresses
      final host = uri.host.toLowerCase();
      final blockedPatterns = [
        'localhost',
        '127.', // Loopback
        '0.0.0.0',
        '10.', // Private class A
        '192.168.', // Private class C
        '169.254.', // Link-local
        '[::1]',
        '::1', // IPv6 localhost
        'fd00:',
        'fe80:', // IPv6 private/link-local
      ];

      // Check for blocked patterns
      if (blockedPatterns.any((pattern) => host.startsWith(pattern))) {
        return Response(
          400,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'error': {
              'code': 'invalid_url',
              'message':
                  'Cannot use internal or private IP addresses in webhook URLs',
            },
          }),
        );
      }

      // Check for private class B (172.16.0.0 - 172.31.255.255)
      if (host.startsWith('172.')) {
        final parts = host.split('.');
        if (parts.length >= 2) {
          final second = int.tryParse(parts[1]);
          if (second != null && second >= 16 && second <= 31) {
            return Response(
              400,
              headers: {'content-type': 'application/json'},
              body: jsonEncode({
                'error': {
                  'code': 'invalid_url',
                  'message':
                      'Cannot use internal or private IP addresses in webhook URLs',
                },
              }),
            );
          }
        }
      }

      return null; // Valid URL
    } catch (e) {
      Logger.debug('Invalid webhook URL format',
          component: 'webhook', metadata: {'url': url, 'error': e.toString()});
      return Response(
        400,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {
            'code': 'invalid_url',
            'message': 'URL must be a valid HTTP/HTTPS URL',
          },
        }),
      );
    }
  }

  /// Get the upstream client (lazy initialization).
  UpstreamClient? get upstream {
    if (!config.enableUpstreamProxy) return null;
    return _upstream ??= UpstreamClient(baseUrl: config.upstreamUrl);
  }

  /// GET `/api/packages`
  Future<Response> listPackages(Request request) async {
    // Check auth if required for downloads
    if (config.requireDownloadAuth) {
      final authResult = await authenticate(
        request,
        lookupToken: metadata.getTokenByHash,
        touchToken: metadata.touchToken,
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }

      // Check read scope
      final token = authResult.token;
      final scopeForbidden = requireReadScope(token);
      if (scopeForbidden != null) {
        return scopeForbidden;
      }
    }

    final page = (int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1)
        .clamp(1, 10000);
    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20)
            .clamp(1, 100);

    final result = await metadata.listPackages(page: page, limit: limit);

    return Response.ok(
      jsonEncode(result.toJson(config.baseUrl)),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/api/packages/search`
  Future<Response> searchPackages(Request request) async {
    // Check auth if required for downloads
    if (config.requireDownloadAuth) {
      final authResult = await authenticate(
        request,
        lookupToken: metadata.getTokenByHash,
        touchToken: metadata.touchToken,
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }

      // Check read scope
      final token = authResult.token;
      final scopeForbidden = requireReadScope(token);
      if (scopeForbidden != null) {
        return scopeForbidden;
      }
    }

    final query = request.url.queryParameters['q'] ?? '';
    if (query.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'missing_query',
            'message': 'Search query is required'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final page = (int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1)
        .clamp(1, 10000);
    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20)
            .clamp(1, 100);

    final result =
        await metadata.searchPackages(query, page: page, limit: limit);

    return Response.ok(
      jsonEncode(result.toJson(config.baseUrl)),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/api/packages/search/upstream`
  /// Search packages from upstream registry (pub.dev)
  Future<Response> searchPackagesUpstream(Request request) async {
    if (upstream == null) {
      return Response(
        503,
        body: jsonEncode({
          'error': {
            'code': 'upstream_disabled',
            'message': 'Upstream proxy is not enabled'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final query = request.url.queryParameters['q'] ?? '';
    if (query.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'missing_query',
            'message': 'Search query is required'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final page = (int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1)
        .clamp(1, 10000);
    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20)
            .clamp(1, 100);

    try {
      final packageNames = await upstream!.searchPackages(query, page: page);

      if (packageNames.isEmpty) {
        return Response.ok(
          jsonEncode({
            'packages': [],
            'total': 0,
            'page': page,
            'limit': limit,
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Fetch full package info in parallel with concurrency limit
      final namesToFetch = packageNames.take(limit).toList();
      final upstreamPackages = await upstream!.getPackagesBatch(namesToFetch);

      final upstreamInfos = upstreamPackages.map((upstreamPkg) {
        return PackageInfo(
          package: Package(
            name: upstreamPkg.name,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            isDiscontinued: upstreamPkg.isDiscontinued,
            replacedBy: upstreamPkg.replacedBy,
          ),
          versions: upstreamPkg.versions.map((v) {
            return PackageVersion(
              packageName: v.packageName,
              version: v.version,
              pubspec: v.pubspec,
              archiveKey: v.archiveUrl,
              archiveSha256: v.archiveSha256 ?? '',
              publishedAt: v.published ?? DateTime.now(),
            );
          }).toList(),
        );
      }).toList();

      final upstreamResult = PackageListResult(
        packages: upstreamInfos,
        total: packageNames.length,
        page: page,
        limit: limit,
      );

      return Response.ok(
        jsonEncode(upstreamResult.toJson(config.baseUrl)),
        headers: {'content-type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.error('Failed to search upstream packages',
          component: 'upstream', error: e, stackTrace: stackTrace);
      return Response(
        500,
        body: jsonEncode({
          'error': {
            'code': 'upstream_error',
            'message': 'Failed to search upstream: $e'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// GET `/api/upstream/packages/<name>`
  /// Get package info from upstream registry (pub.dev)
  Future<Response> getUpstreamPackage(Request request, String name) async {
    if (upstream == null) {
      return Response(
        503,
        body: jsonEncode({
          'error': {
            'code': 'upstream_disabled',
            'message': 'Upstream proxy is not enabled'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    try {
      final upstreamPkg = await upstream!.getPackage(name);

      if (upstreamPkg == null) {
        return Response.notFound(
          jsonEncode({
            'error': {
              'code': 'not_found',
              'message': 'Package not found on upstream'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return _buildUpstreamPackageResponse(upstreamPkg);
    } catch (e, stackTrace) {
      Logger.error('Failed to fetch upstream package',
          component: 'upstream',
          error: e,
          stackTrace: stackTrace,
          metadata: {'package': name});
      return Response(
        500,
        body: jsonEncode({
          'error': {
            'code': 'upstream_error',
            'message': 'Failed to fetch upstream package: $e'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// GET `/api/packages/<name>`
  Future<Response> getPackage(Request request, String name) async {
    // Check auth if required for downloads
    if (config.requireDownloadAuth) {
      final authResult = await authenticate(
        request,
        lookupToken: metadata.getTokenByHash,
        touchToken: metadata.touchToken,
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }

      // Check read scope
      final token = authResult.token;
      final scopeForbidden = requireReadScope(token);
      if (scopeForbidden != null) {
        return scopeForbidden;
      }
    }

    final info = await metadata.getPackageInfo(name);

    // If not found locally, try upstream
    if (info == null && upstream != null) {
      final upstreamInfo = await upstream!.getPackage(name);
      if (upstreamInfo != null) {
        // Return upstream info directly (don't cache metadata, only cache on download)
        return _buildUpstreamPackageResponse(upstreamInfo);
      }
    }

    if (info == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Package not found: $name'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Build version list with archive URLs
    final versions = <Map<String, dynamic>>[];
    for (final v in info.versions) {
      final archiveUrl =
          '${config.baseUrl}/packages/${v.packageName}/versions/${v.version}.tar.gz';
      versions.add(v.toJson(archiveUrl));
    }

    final latest = info.latest;
    final latestArchiveUrl = latest != null
        ? '${config.baseUrl}/packages/${latest.packageName}/versions/${latest.version}.tar.gz'
        : null;

    final response = {
      'name': info.package.name,
      if (latest != null) 'latest': latest.toJson(latestArchiveUrl!),
      'versions': versions,
      if (info.package.isDiscontinued) 'isDiscontinued': true,
      if (info.package.replacedBy != null)
        'replacedBy': info.package.replacedBy,
    };

    return Response.ok(
      jsonEncode(response),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/api/packages/<name>/versions/<version>`
  Future<Response> getVersion(
      Request request, String name, String version) async {
    // Check auth if required for downloads
    if (config.requireDownloadAuth) {
      final authResult = await authenticate(
        request,
        lookupToken: metadata.getTokenByHash,
        touchToken: metadata.touchToken,
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }

      // Check read scope
      final token = authResult.token;
      final scopeForbidden = requireReadScope(token);
      if (scopeForbidden != null) {
        return scopeForbidden;
      }
    }

    final versionInfo = await metadata.getPackageVersion(name, version);

    // If not found locally, try upstream
    if (versionInfo == null && upstream != null) {
      final upstreamVersion = await upstream!.getVersion(name, version);
      if (upstreamVersion != null) {
        // Return upstream version info with our archive URL
        final archiveUrl =
            '${config.baseUrl}/packages/$name/versions/$version.tar.gz';
        return Response.ok(
          jsonEncode({
            'version': upstreamVersion.version,
            'pubspec': upstreamVersion.pubspec,
            'archive_url': archiveUrl,
            if (upstreamVersion.archiveSha256 != null)
              'archive_sha256': upstreamVersion.archiveSha256,
            if (upstreamVersion.published != null)
              'published': upstreamVersion.published!.toIso8601String(),
          }),
          headers: {'content-type': 'application/json'},
        );
      }
    }

    if (versionInfo == null) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'not_found',
            'message': 'Version $version of package $name not found',
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final archiveUrl =
        '${config.baseUrl}/packages/${versionInfo.packageName}/versions/${versionInfo.version}.tar.gz';

    return Response.ok(
      jsonEncode(versionInfo.toJson(archiveUrl)),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/packages/versions/new
  Future<Response> initiateUpload(Request request) async {
    // Check auth if required for publishing
    if (config.requirePublishAuth) {
      final authResult = await authenticate(
        request,
        lookupToken: metadata.getTokenByHash,
        touchToken: metadata.touchToken,
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }
    }

    // Create upload session
    final session = await metadata.createUploadSession();

    final uploadUrl =
        '${config.baseUrl}/api/packages/versions/upload/${session.id}';

    return Response.ok(
      jsonEncode({
        'url': uploadUrl,
        'fields': <String, String>{},
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST `/api/packages/versions/upload/<sessionId>`
  Future<Response> uploadPackage(Request request, String sessionId) async {
    // Check auth if required for publishing
    if (config.requirePublishAuth) {
      final authResult = await authenticate(
        request,
        lookupToken: metadata.getTokenByHash,
        touchToken: metadata.touchToken,
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }
    }

    // Validate session
    final session = await metadata.getUploadSession(sessionId);
    if (session == null) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'invalid_session',
            'message': 'Invalid or expired upload session'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    if (session.isExpired) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'expired_session',
            'message': 'Upload session has expired'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Read the request body
    final contentType = request.headers['content-type'] ?? '';
    Uint8List tarballBytes;

    if (contentType.contains('multipart/form-data')) {
      tarballBytes = await _parseMultipartUpload(request);
    } else {
      tarballBytes = await _readRequestBody(request);
    }

    if (tarballBytes.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'error': {'code': 'empty_upload', 'message': 'No file data received'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Check upload size limit
    if (tarballBytes.length > config.maxUploadSizeBytes) {
      final maxSizeMb = config.maxUploadSizeBytes / (1024 * 1024);
      Logger.warn(
        'Upload rejected: exceeds size limit',
        component: 'upload',
        metadata: {
          'sessionId': sessionId,
          'uploadSize': tarballBytes.length,
          'maxSize': config.maxUploadSizeBytes,
        },
      );
      return Response(
        413,
        body: jsonEncode({
          'error': {
            'code': 'payload_too_large',
            'message':
                'Upload size exceeds maximum allowed (${maxSizeMb.toStringAsFixed(0)}MB)',
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Store temporarily with creation time for TTL-based cleanup
    _uploadData[sessionId] = tarballBytes;
    _uploadSessionCreatedAt[sessionId] = DateTime.now();

    // Respond with 204 and Location header for finalize
    final finalizeUrl =
        '${config.baseUrl}/api/packages/versions/finalize/$sessionId';
    return Response(
      204,
      headers: {'location': finalizeUrl},
    );
  }

  /// GET `/api/packages/versions/finalize/<sessionId>`
  Future<Response> finalizeUpload(Request request, String sessionId) async {
    // Check auth if required for publishing
    AuthToken? token;
    if (config.requirePublishAuth) {
      final authResult = await authenticate(
        request,
        lookupToken: metadata.getTokenByHash,
        touchToken: metadata.touchToken,
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }
      token = authResult.token;
    }

    // Get upload data
    final tarballBytes = _uploadData[sessionId];
    if (tarballBytes == null) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'no_upload',
            'message': 'No upload data found for session'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Validate session
    final session = await metadata.getUploadSession(sessionId);
    if (session == null) {
      _uploadData.remove(sessionId);
      _uploadSessionCreatedAt.remove(sessionId);
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'invalid_session',
            'message': 'Invalid or expired upload session'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Validate tarball
    final result = await validateTarball(tarballBytes);

    if (result is PublishError) {
      _uploadData.remove(sessionId);
      _uploadSessionCreatedAt.remove(sessionId);
      return Response(
        400,
        body: jsonEncode({
          'error': {'code': 'validation_error', 'message': result.message},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final success = result as PublishSuccess;

    // Check scope authorization if token is present
    if (token != null) {
      final scopeForbidden =
          requirePackagePublishScope(token, success.packageName);
      if (scopeForbidden != null) {
        _uploadData.remove(sessionId);
        _uploadSessionCreatedAt.remove(sessionId);
        return scopeForbidden;
      }
    }

    // Determine the user ID for ownership
    final userId = token?.userId ?? User.anonymousId;

    // Check publish permission based on package ownership
    final existingPackage = await metadata.getPackage(success.packageName);
    if (existingPackage != null && !existingPackage.canPublish(userId)) {
      _uploadData.remove(sessionId);
      _uploadSessionCreatedAt.remove(sessionId);
      return forbidden(
          'Not authorized to publish package: ${success.packageName}');
    }

    // Check if version already exists
    if (await metadata.versionExists(success.packageName, success.version)) {
      _uploadData.remove(sessionId);
      _uploadSessionCreatedAt.remove(sessionId);
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'version_exists',
            'message':
                'Version ${success.version} of ${success.packageName} already exists',
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Store to S3
    final archiveKey = blobs.archiveKey(
      success.packageName,
      success.version,
      success.sha256Hash,
    );
    await blobs.putArchive(key: archiveKey, data: success.tarballBytes);

    // Store metadata (set ownerId only for new packages)
    await metadata.upsertPackageVersion(
      packageName: success.packageName,
      version: success.version,
      pubspec: success.pubspec,
      archiveKey: archiveKey,
      archiveSha256: success.sha256Hash,
      ownerId: existingPackage == null ? userId : null,
    );

    // Mark session complete
    await metadata.completeUploadSession(sessionId);

    // Log activity
    final user = token != null ? await metadata.getUser(token.userId) : null;
    await metadata.logActivity(
      activityType: 'package_published',
      actorType: user != null ? 'user' : 'system',
      actorId: user?.id,
      actorEmail: user?.email,
      targetType: 'package',
      targetId: success.packageName,
      metadata: {'version': success.version},
      ipAddress: _extractClientIp(request),
    );

    // Trigger webhook (fire-and-forget with error logging)
    _triggerWebhook(
      () => webhooks.onPackagePublished(
        packageName: success.packageName,
        version: success.version,
        publisherEmail: user?.email,
      ),
      'package.published',
    );

    // Send email notification (fire-and-forget with error logging)
    if (user?.email != null) {
      _sendEmail(
        () => emails.onPackagePublished(
          packageName: success.packageName,
          version: success.version,
          publisherEmail: user!.email,
          baseUrl: config.baseUrl,
        ),
        'package_published',
      );
    }

    // Clean up
    _uploadData.remove(sessionId);
    _uploadSessionCreatedAt.remove(sessionId);

    return Response.ok(
      jsonEncode({
        'success': {
          'message':
              'Successfully published ${success.packageName} ${success.version}',
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/packages/<name>/versions/<version>.tar.gz`
  Future<Response> downloadPackage(
    Request request,
    String name,
    String version,
  ) async {
    // Extract IP address and user agent for analytics
    final ipAddress = _extractClientIp(request);
    final userAgent = request.headers['user-agent'];

    // Check auth if required
    if (config.requireDownloadAuth) {
      final authResult = await authenticate(
        request,
        lookupToken: metadata.getTokenByHash,
        touchToken: metadata.touchToken,
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }

      // Check read scope
      final token = authResult.token;
      final scopeForbidden = requireReadScope(token);
      if (scopeForbidden != null) {
        return scopeForbidden;
      }
    }

    // Get version info from database
    final versionInfo = await metadata.getPackageVersion(name, version);

    // If found in database, serve from appropriate storage
    if (versionInfo != null) {
      try {
        // Check if this is a cached upstream package
        final pkgInfo = await metadata.getPackageInfo(name);
        final isCache = pkgInfo?.package.isUpstreamCache ?? false;
        final store = isCache ? cacheBlobs : blobs;

        final bytes = await store.getArchive(versionInfo.archiveKey);

        // Log download for analytics
        await metadata.logDownload(
          packageName: name,
          version: version,
          ipAddress: ipAddress,
          userAgent: userAgent,
        );

        return Response.ok(
          Stream.value(bytes),
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': bytes.length.toString(),
          },
        );
      } catch (e) {
        // If storage fails, try upstream
        Logger.warn('Storage error fetching archive',
            component: 'storage',
            error: e,
            metadata: {
              'package': name,
              'version': version,
            });
      }
    }

    // Try to fetch from upstream and cache
    if (upstream != null) {
      final upstreamVersion = await upstream!.getVersion(name, version);
      if (upstreamVersion != null && upstreamVersion.archiveUrl.isNotEmpty) {
        Logger.debug('Fetching from upstream',
            component: 'upstream',
            metadata: {
              'package': name,
              'version': version,
              'url': upstreamVersion.archiveUrl,
            });
        final archiveBytes =
            await upstream!.downloadArchive(upstreamVersion.archiveUrl);

        if (archiveBytes != null) {
          // Cache the archive in cache storage
          try {
            final sha256Hash = sha256.convert(archiveBytes).toString();
            final archiveKey = cacheBlobs.archiveKey(name, version, sha256Hash);

            // Store to cache blob storage
            await cacheBlobs.putArchive(key: archiveKey, data: archiveBytes);

            // Store metadata (cache the package info)
            await metadata.upsertPackageVersion(
              packageName: name,
              version: version,
              pubspec: upstreamVersion.pubspec,
              archiveKey: archiveKey,
              archiveSha256: sha256Hash,
              isUpstreamCache: true,
            );

            Logger.info('Cached package from upstream',
                component: 'cache',
                metadata: {
                  'package': name,
                  'version': version,
                });

            // Log download for analytics
            await metadata.logDownload(
              packageName: name,
              version: version,
              ipAddress: ipAddress,
              userAgent: userAgent,
            );

            return Response.ok(
              Stream.value(archiveBytes),
              headers: {
                'content-type': 'application/octet-stream',
                'content-length': archiveBytes.length.toString(),
              },
            );
          } catch (e) {
            Logger.warn('Failed to cache package from upstream',
                component: 'cache',
                error: e,
                metadata: {
                  'package': name,
                  'version': version,
                });

            // Log download for analytics (even if caching failed)
            await metadata.logDownload(
              packageName: name,
              version: version,
              ipAddress: ipAddress,
              userAgent: userAgent,
            );

            // Still return the archive even if caching failed
            return Response.ok(
              Stream.value(archiveBytes),
              headers: {
                'content-type': 'application/octet-stream',
                'content-length': archiveBytes.length.toString(),
              },
            );
          }
        }
      }
    }

    return Response.notFound(
      jsonEncode({
        'error': {
          'code': 'not_found',
          'message': 'Version $version of package $name not found',
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Build response for upstream package info.
  Response _buildUpstreamPackageResponse(UpstreamPackageInfo info) {
    // Build version list with our archive URLs
    final versions = <Map<String, dynamic>>[];
    for (final v in info.versions) {
      final archiveUrl =
          '${config.baseUrl}/packages/${info.name}/versions/${v.version}.tar.gz';
      versions.add({
        'version': v.version,
        'pubspec': v.pubspec,
        'archive_url': archiveUrl,
        if (v.archiveSha256 != null) 'archive_sha256': v.archiveSha256,
        if (v.published != null) 'published': v.published!.toIso8601String(),
      });
    }

    final latest = info.latest;
    Map<String, dynamic>? latestJson;
    if (latest != null) {
      final latestArchiveUrl =
          '${config.baseUrl}/packages/${info.name}/versions/${latest.version}.tar.gz';
      latestJson = {
        'version': latest.version,
        'pubspec': latest.pubspec,
        'archive_url': latestArchiveUrl,
        if (latest.archiveSha256 != null)
          'archive_sha256': latest.archiveSha256,
        if (latest.published != null)
          'published': latest.published!.toIso8601String(),
      };
    }

    final response = {
      'name': info.name,
      if (latestJson != null) 'latest': latestJson,
      'versions': versions,
      if (info.isDiscontinued) 'isDiscontinued': true,
      if (info.replacedBy != null) 'replacedBy': info.replacedBy,
    };

    return Response.ok(
      jsonEncode(response),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Uint8List> _parseMultipartUpload(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    final boundaryMatch = RegExp(r'boundary=(.+)$').firstMatch(contentType);
    if (boundaryMatch == null) {
      return Uint8List(0);
    }

    final boundary = boundaryMatch.group(1)!;
    final boundaryBytes = utf8.encode('--$boundary');
    final body = await _readRequestBody(request);

    // Find boundary positions in raw bytes
    final headerEndMarker = utf8.encode('\r\n\r\n');
    final endMarker = utf8.encode('\r\n--');

    int pos = 0;
    while (pos < body.length) {
      // Find next boundary
      final boundaryPos = _indexOf(body, boundaryBytes, pos);
      if (boundaryPos == -1) break;

      // Find header end
      final headerEndPos =
          _indexOf(body, headerEndMarker, boundaryPos + boundaryBytes.length);
      if (headerEndPos == -1) {
        pos = boundaryPos + boundaryBytes.length;
        continue;
      }

      // Check if this part contains file data by looking at headers
      final headerBytes = body.sublist(boundaryPos + boundaryBytes.length,
          headerEndPos + headerEndMarker.length);
      final headerStr = utf8.decode(headerBytes, allowMalformed: true);

      if (headerStr.contains('filename=') ||
          headerStr.contains('name="file"')) {
        final contentStart = headerEndPos + headerEndMarker.length;

        // Find the next boundary or end
        final nextBoundaryPos = _indexOf(body, endMarker, contentStart);
        final contentEnd =
            nextBoundaryPos != -1 ? nextBoundaryPos : body.length;

        if (contentEnd > contentStart) {
          return Uint8List.sublistView(body, contentStart, contentEnd);
        }
      }

      pos = headerEndPos + headerEndMarker.length;
    }

    return Uint8List(0);
  }

  /// Find the index of a pattern in a byte list.
  int _indexOf(Uint8List haystack, List<int> needle, int start) {
    outer:
    for (var i = start; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  Response _authErrorResponse(AuthResult result) {
    switch (result) {
      case AuthMissing():
        return unauthorized('Authentication required');
      case AuthInvalid(:final message):
        return unauthorized(message);
      case AuthForbidden(:final message):
        return forbidden(message);
      case AuthSuccess():
        throw StateError('Should not reach here');
    }
  }

  // ============ Admin Handlers ============
  // Note: Admin endpoints have no built-in auth.
  // Use external auth (reverse proxy, HTTP Basic Auth, etc.)

  /// GET `/api/admin/stats`
  Future<Response> adminGetStats(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final stats = await metadata.getAdminStats();

    return Response.ok(
      jsonEncode(stats.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/analytics/packages-created`
  Future<Response> adminGetPackagesCreatedPerDay(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final days =
        int.tryParse(request.url.queryParameters['days'] ?? '30') ?? 30;
    final data = await metadata.getPackagesCreatedPerDay(days);

    return Response.ok(
      jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/analytics/downloads`
  Future<Response> adminGetDownloadsPerHour(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final hours =
        int.tryParse(request.url.queryParameters['hours'] ?? '24') ?? 24;
    final data = await metadata.getDownloadsPerHour(hours);

    return Response.ok(
      jsonEncode(data),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/activity`
  Future<Response> adminGetRecentActivity(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '10') ?? 10;
    final activityType = request.url.queryParameters['type'];
    final actorType = request.url.queryParameters['actor'];

    final activities = await metadata.getRecentActivity(
      limit: limit,
      activityType: activityType,
      actorType: actorType,
    );

    return Response.ok(
      jsonEncode({
        'activities': activities.map((a) => a.toJson()).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/export/packages` - Export packages list as CSV
  Future<Response> adminExportPackagesCsv(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '1000') ?? 1000)
            .clamp(1, 10000);
    final isUpstreamCache =
        request.url.queryParameters['type'] == 'cached' ? true : false;

    final result = await metadata.listPackagesByType(
      isUpstreamCache: isUpstreamCache,
      page: 1,
      limit: limit,
    );

    // Flatten package data for CSV
    final rows = result.packages.map((pkg) {
      return {
        'name': pkg.package.name,
        'latest_version': pkg.latest?.version ?? '',
        'description': pkg.latest?.pubspec['description']?.toString() ?? '',
        'is_discontinued': pkg.package.isDiscontinued ? 'yes' : 'no',
        'replaced_by': pkg.package.replacedBy ?? '',
        'total_versions': pkg.versions.length.toString(),
        'is_upstream_cache': isUpstreamCache ? 'yes' : 'no',
      };
    }).toList();

    final csv = mapListToCsv(rows);
    final filename =
        isUpstreamCache ? 'cached_packages.csv' : 'hosted_packages.csv';

    return Response.ok(
      csv,
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="$filename"',
      },
    );
  }

  /// GET `/admin/api/export/activity` - Export activity log as CSV
  Future<Response> adminExportActivityCsv(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '1000') ?? 1000)
            .clamp(1, 10000);
    final activityType = request.url.queryParameters['type'];
    final actorType = request.url.queryParameters['actor'];

    final activities = await metadata.getRecentActivity(
      limit: limit,
      activityType: activityType,
      actorType: actorType,
    );

    // Convert to CSV-friendly format
    final rows = activities.map((activity) {
      return {
        'timestamp': activity.timestamp.toIso8601String(),
        'activity_type': activity.activityType,
        'actor_type': activity.actorType,
        'actor_email': activity.actorEmail ?? '',
        'actor_username': activity.actorUsername ?? '',
        'target_type': activity.targetType ?? '',
        'target_id': activity.targetId ?? '',
        'ip_address': activity.ipAddress ?? '',
        'description': activity.description,
      };
    }).toList();

    final csv = mapListToCsv(rows);

    return Response.ok(
      csv,
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="activity_log.csv"',
      },
    );
  }

  /// GET `/admin/api/export/downloads` - Export download statistics as CSV
  Future<Response> adminExportDownloadsCsv(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '10000') ?? 10000;

    // Fetch raw download records (we'll need to add a method for this)
    // For now, we'll export aggregated data per package
    final packages = await metadata.listPackagesByType(
      isUpstreamCache: false,
      page: 1,
      limit: 100, // Top 100 packages
    );

    // Track packages with their download counts for sorting
    final packageData = <({String name, int downloads, String version})>[];

    for (final pkg in packages.packages) {
      final stats = await metadata.getPackageDownloadStats(pkg.package.name);
      if (stats.totalDownloads > 0) {
        packageData.add((
          name: pkg.package.name,
          downloads: stats.totalDownloads,
          version: pkg.latest?.version ?? '',
        ));
      }
    }

    // Sort by downloads descending
    packageData.sort((a, b) => b.downloads.compareTo(a.downloads));

    // Convert to CSV rows
    final rows = packageData
        .map((p) => {
              'package_name': p.name,
              'total_downloads': p.downloads.toString(),
              'latest_version': p.version,
            })
        .toList();

    final csv = mapListToCsv(rows.take(limit).toList());

    return Response.ok(
      csv,
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="download_stats.csv"',
      },
    );
  }

  /// GET `/admin/api/hosted-packages`
  Future<Response> adminListHostedPackages(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final page = (int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1)
        .clamp(1, 10000);
    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20)
            .clamp(1, 100);

    final result = await metadata.listPackagesByType(
      isUpstreamCache: false,
      page: page,
      limit: limit,
    );

    return Response.ok(
      jsonEncode(result.toJson(config.baseUrl)),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/cached-packages`
  Future<Response> adminListCachedPackages(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final page = (int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1)
        .clamp(1, 10000);
    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20)
            .clamp(1, 100);

    final result = await metadata.listPackagesByType(
      isUpstreamCache: true,
      page: page,
      limit: limit,
    );

    return Response.ok(
      jsonEncode(result.toJson(config.baseUrl)),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/packages/<name>/stats`
  Future<Response> adminGetPackageStats(Request request, String name) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Get package info first to verify it exists
    final pkgInfo = await metadata.getPackageInfo(name);
    if (pkgInfo == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Package not found: $name'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Get download statistics
    final days =
        int.tryParse(request.url.queryParameters['days'] ?? '30') ?? 30;
    final stats =
        await metadata.getPackageDownloadStats(name, historyDays: days);

    return Response.ok(
      jsonEncode({
        'package': pkgInfo.package.toJson(),
        'version_count': pkgInfo.versions.length,
        'latest_version': pkgInfo.latest?.version,
        'stats': stats.toJson(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/packages/<name>/versions`
  Future<Response> adminGetPackageVersions(Request request, String name) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final pkgInfo = await metadata.getPackageInfo(name);
    if (pkgInfo == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Package not found: $name'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final versions = pkgInfo.versions
        .map((v) => {
              'version': v.version,
              'published_at': v.publishedAt.toIso8601String(),
              'is_retracted': v.isRetracted,
              'retracted_at': v.retractedAt?.toIso8601String(),
            })
        .toList();

    // Sort by version descending (latest first)
    versions.sort(
        (a, b) => (b['version'] as String).compareTo(a['version'] as String));

    return Response.ok(
      jsonEncode({
        'package': name,
        'versions': versions,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// DELETE `/api/admin/packages/<name>`
  Future<Response> adminDeletePackage(Request request, String name) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Check if this is a cached package before deleting
    final pkgInfo = await metadata.getPackageInfo(name);
    final isCache = pkgInfo?.package.isUpstreamCache ?? false;
    final store = isCache ? cacheBlobs : blobs;

    // Get archive keys before deleting metadata
    final archiveKeys = await metadata.getPackageArchiveKeys(name);

    // Delete metadata
    final versionCount = await metadata.deletePackage(name);

    if (versionCount == 0 && archiveKeys.isEmpty) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Package not found: $name'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Delete blobs from appropriate storage
    for (final key in archiveKeys) {
      try {
        await store.delete(key);
      } catch (e) {
        Logger.warn('Failed to delete blob',
            component: 'storage', error: e, metadata: {'key': key});
      }
    }

    // Log activity
    final adminUser = await _getAdminFromSession(request);
    await metadata.logActivity(
      activityType: isCache ? 'cache_cleared' : 'package_deleted',
      actorType: 'admin',
      actorId: adminUser?.id,
      actorUsername: adminUser?.username,
      targetType: 'package',
      targetId: name,
      metadata: {'versionCount': versionCount},
      ipAddress: _extractClientIp(request),
    );

    return Response.ok(
      jsonEncode({
        'success': {
          'message': 'Deleted package $name with $versionCount version(s)',
          'versionsDeleted': versionCount,
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// DELETE `/api/admin/packages/<name>/versions/<version>`
  Future<Response> adminDeletePackageVersion(
    Request request,
    String name,
    String version,
  ) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Check if this is a cached package before deleting
    final pkgInfo = await metadata.getPackageInfo(name);
    final isCache = pkgInfo?.package.isUpstreamCache ?? false;
    final store = isCache ? cacheBlobs : blobs;

    // Get archive key before deleting metadata
    final archiveKey = await metadata.getVersionArchiveKey(name, version);

    // Delete metadata
    final deleted = await metadata.deletePackageVersion(name, version);

    if (!deleted) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'not_found',
            'message': 'Version $version of package $name not found',
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Delete blob from appropriate storage
    if (archiveKey != null) {
      try {
        await store.delete(archiveKey);
      } catch (e) {
        Logger.warn('Failed to delete blob',
            component: 'storage', error: e, metadata: {'key': archiveKey});
      }
    }

    return Response.ok(
      jsonEncode({
        'success': {
          'message': 'Deleted version $version of package $name',
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST `/admin/api/packages/<name>/versions/<version>/retract`
  Future<Response> adminRetractPackageVersion(
    Request request,
    String name,
    String version,
  ) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Parse optional retraction message from request body
    String? retractionMessage;
    try {
      final body = await request.readAsString();
      if (body.isNotEmpty) {
        final json = jsonDecode(body) as Map<String, dynamic>;
        retractionMessage = json['message'] as String?;
      }
    } catch (e) {
      // Ignore JSON parsing errors - message is optional
    }

    final retracted = await metadata.retractPackageVersion(
      name,
      version,
      message: retractionMessage,
    );

    if (!retracted) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'not_found',
            'message': 'Version $version of package $name not found',
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Log activity
    final adminUser = request.context['adminUser'] as Map<String, dynamic>?;
    await metadata.logActivity(
      activityType: 'version_retracted',
      actorType: 'admin',
      actorId: adminUser?['username'] as String? ?? 'unknown',
      targetType: 'package_version',
      targetId: '$name@$version',
      metadata: {
        'package': name,
        'version': version,
        if (retractionMessage != null) 'message': retractionMessage,
      },
      ipAddress:
          request.headers['x-forwarded-for'] ?? request.headers['x-real-ip'],
    );

    return Response.ok(
      jsonEncode({
        'success': {
          'message': 'Retracted version $version of package $name',
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// DELETE `/admin/api/packages/<name>/versions/<version>/retract`
  Future<Response> adminUnretractPackageVersion(
    Request request,
    String name,
    String version,
  ) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final unretracted = await metadata.unretractPackageVersion(name, version);

    if (!unretracted) {
      return Response.notFound(
        jsonEncode({
          'error': {
            'code': 'not_found',
            'message': 'Version $version of package $name not found',
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Log activity
    final adminUser = request.context['adminUser'] as Map<String, dynamic>?;
    await metadata.logActivity(
      activityType: 'version_unretracted',
      actorType: 'admin',
      actorId: adminUser?['username'] as String? ?? 'unknown',
      targetType: 'package_version',
      targetId: '$name@$version',
      metadata: {'package': name, 'version': version},
      ipAddress:
          request.headers['x-forwarded-for'] ?? request.headers['x-real-ip'],
    );

    return Response.ok(
      jsonEncode({
        'success': {
          'message': 'Unretracted version $version of package $name',
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/packages/<name>/dependencies`
  ///
  /// Returns dependency information for a package:
  /// - Direct dependencies from latest version
  /// - Reverse dependencies (packages that depend on this one)
  /// - Dependency tree (dependencies of dependencies, depth-limited)
  Future<Response> adminGetPackageDependencies(
    Request request,
    String name,
  ) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final info = await metadata.getPackageInfo(name);
    if (info == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Package not found: $name'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final latest = info.latest;
    if (latest == null) {
      return Response.ok(
        jsonEncode({
          'package': name,
          'dependencies': <String, dynamic>{},
          'dev_dependencies': <String, dynamic>{},
          'reverse_dependencies': <String>[],
          'dependency_tree': <String, dynamic>{},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Get depth parameter (default 2, max 5)
    final depth =
        int.tryParse(request.requestedUri.queryParameters['depth'] ?? '2') ?? 2;
    final maxDepth = depth.clamp(1, 5);

    // Extract direct dependencies from pubspec
    final pubspec = latest.pubspec;
    final dependencies =
        (pubspec['dependencies'] as Map<String, dynamic>?) ?? {};
    final devDependencies =
        (pubspec['dev_dependencies'] as Map<String, dynamic>?) ?? {};

    // Find reverse dependencies (packages that depend on this package)
    final reverseDeps = await _findReverseDependencies(name);

    // Build dependency tree (dependencies of dependencies)
    final dependencyTree = await _buildDependencyTree(
      dependencies.keys.toList(),
      maxDepth,
      visited: {name},
    );

    return Response.ok(
      jsonEncode({
        'package': name,
        'version': latest.version,
        'dependencies': dependencies,
        'dev_dependencies': devDependencies,
        'reverse_dependencies': reverseDeps,
        'dependency_tree': dependencyTree,
        'environment': pubspec['environment'] ?? {},
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// Find packages that depend on the given package.
  Future<List<Map<String, dynamic>>> _findReverseDependencies(
      String packageName) async {
    final result = <Map<String, dynamic>>[];

    // Get all hosted packages
    final packages = await metadata.listPackagesByType(
      isUpstreamCache: false,
      page: 1,
      limit: 1000,
    );
    for (final pkg in packages.packages) {
      final latest = pkg.latest;
      if (latest == null) continue;

      final dependencies =
          (latest.pubspec['dependencies'] as Map<String, dynamic>?) ?? {};
      final devDependencies =
          (latest.pubspec['dev_dependencies'] as Map<String, dynamic>?) ?? {};

      if (dependencies.containsKey(packageName)) {
        result.add({
          'name': pkg.package.name,
          'version': latest.version,
          'constraint': dependencies[packageName],
          'type': 'dependency',
        });
      } else if (devDependencies.containsKey(packageName)) {
        result.add({
          'name': pkg.package.name,
          'version': latest.version,
          'constraint': devDependencies[packageName],
          'type': 'dev_dependency',
        });
      }
    }

    return result;
  }

  /// Build a dependency tree showing transitive dependencies.
  Future<Map<String, dynamic>> _buildDependencyTree(
    List<String> dependencies,
    int depth, {
    Set<String>? visited,
  }) async {
    if (depth <= 0) return {};

    final effectiveVisited = visited ?? <String>{};
    final tree = <String, dynamic>{};

    for (final depName in dependencies) {
      if (effectiveVisited.contains(depName)) {
        tree[depName] = {'circular': true};
        continue;
      }

      final depInfo = await metadata.getPackageInfo(depName);
      if (depInfo == null) {
        tree[depName] = {'external': true};
        continue;
      }

      final latest = depInfo.latest;
      if (latest == null) {
        tree[depName] = {'no_versions': true};
        continue;
      }

      final depDeps =
          (latest.pubspec['dependencies'] as Map<String, dynamic>?) ?? {};

      if (depDeps.isEmpty) {
        tree[depName] = {'version': latest.version, 'dependencies': {}};
      } else {
        final subTree = await _buildDependencyTree(
          depDeps.keys.toList(),
          depth - 1,
          visited: {...effectiveVisited, depName},
        );
        tree[depName] = {
          'version': latest.version,
          'dependencies': subTree,
        };
      }
    }

    return tree;
  }

  /// POST `/admin/api/packages/<name>/transfer`
  ///
  /// Transfer package ownership to a new user.
  /// Request body: {"newOwnerId": "user-uuid"}
  Future<Response> adminTransferPackageOwnership(
    Request request,
    String name,
  ) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Parse body for newOwnerId
    String? newOwnerId;
    try {
      final bodyBytes = await _readRequestBody(request);
      if (bodyBytes.isNotEmpty) {
        final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
        newOwnerId = body['newOwnerId'] as String?;
      }
    } catch (e) {
      return _errorResponse(400, 'bad_request', 'Invalid request body');
    }

    if (newOwnerId == null || newOwnerId.isEmpty) {
      return _errorResponse(400, 'bad_request', 'newOwnerId is required');
    }

    // Get current package info for logging
    final existingPackage = await metadata.getPackage(name);
    if (existingPackage == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Package not found: $name'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final oldOwnerId = existingPackage.ownerId;

    // Perform transfer
    final success = await metadata.transferPackageOwnership(name, newOwnerId);

    if (!success) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'transfer_failed',
            'message':
                'Failed to transfer ownership. Check that the new owner exists.',
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Log activity
    final adminUser = request.context['adminUser'] as Map<String, dynamic>?;
    await metadata.logActivity(
      activityType: 'package_ownership_transferred',
      actorType: 'admin',
      actorId: adminUser?['username'] as String? ?? 'unknown',
      targetType: 'package',
      targetId: name,
      metadata: {
        'package': name,
        'oldOwnerId': oldOwnerId,
        'newOwnerId': newOwnerId,
      },
      ipAddress:
          request.headers['x-forwarded-for'] ?? request.headers['x-real-ip'],
    );

    return Response.ok(
      jsonEncode({
        'success': {
          'message': 'Package ownership transferred',
          'package': name,
          'oldOwnerId': oldOwnerId,
          'newOwnerId': newOwnerId,
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST `/api/admin/packages/<name>/discontinue`
  Future<Response> adminDiscontinuePackage(Request request, String name) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Parse body for optional replacedBy
    String? replacedBy;
    try {
      final bodyBytes = await _readRequestBody(request);
      if (bodyBytes.isNotEmpty) {
        final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
        replacedBy = body['replacedBy'] as String?;
      }
    } catch (e) {
      // Body parsing errors are acceptable for this optional field
      Logger.debug('Could not parse discontinue body',
          component: 'admin',
          metadata: {'package': name, 'error': e.toString()});
    }

    final success =
        await metadata.discontinuePackage(name, replacedBy: replacedBy);

    if (!success) {
      return _errorResponse(404, 'not_found', 'Package not found: $name');
    }

    return _jsonResponse({
      'success': {
        'message': 'Package $name marked as discontinued',
        if (replacedBy != null) 'replacedBy': replacedBy,
      },
    });
  }

  /// DELETE `/api/admin/cache`
  Future<Response> adminClearCache(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Get all archive keys for cached packages before deleting
    final cachedResult = await metadata.listPackagesByType(
      isUpstreamCache: true,
      page: 1,
      limit: 10000, // Get all cached packages
    );

    final allArchiveKeys = <String>[];
    for (final pkg in cachedResult.packages) {
      final keys = await metadata.getPackageArchiveKeys(pkg.package.name);
      allArchiveKeys.addAll(keys);
    }

    // Delete metadata
    final packageCount = await metadata.clearAllCachedPackages();

    // Delete blobs from cache storage
    var blobsDeleted = 0;
    for (final key in allArchiveKeys) {
      try {
        await cacheBlobs.delete(key);
        blobsDeleted++;
      } catch (e) {
        Logger.warn('Failed to delete cached blob',
            component: 'cache', error: e, metadata: {'key': key});
      }
    }

    return Response.ok(
      jsonEncode({
        'success': {
          'message': 'Cleared $packageCount cached package(s)',
          'packagesDeleted': packageCount,
          'blobsDeleted': blobsDeleted,
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/users`
  Future<Response> adminListUsers(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final page = (int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1)
        .clamp(1, 10000);
    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20)
            .clamp(1, 100);

    final users = await metadata.listUsers(page: page, limit: limit);

    return Response.ok(
      jsonEncode({
        'users': users.map((u) => u.toJson()).toList(),
        'page': page,
        'limit': limit,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST `/admin/api/users`
  Future<Response> adminCreateUser(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final email = json['email'] as String?;
    final password = json['password'] as String?;
    final name = json['name'] as String?;

    if (email == null || email.isEmpty) {
      return Response(400,
          body: jsonEncode({
            'error': {'code': 'missing_email', 'message': 'Email is required'}
          }),
          headers: {'content-type': 'application/json'});
    }

    // Check if user already exists
    final existing = await metadata.getUserByEmail(email);
    if (existing != null) {
      return Response(409,
          body: jsonEncode({
            'error': {
              'code': 'user_exists',
              'message': 'User with this email already exists'
            }
          }),
          headers: {'content-type': 'application/json'});
    }

    // Hash password if provided
    String? passwordHash;
    if (password != null && password.isNotEmpty) {
      passwordHash = hashPassword(password);
    }

    final userId = await metadata.createUser(
      email: email,
      passwordHash: passwordHash,
      name: name,
    );

    final user = await metadata.getUser(userId);
    if (user == null) {
      return _errorResponse(500, 'create_failed', 'Failed to create user');
    }

    return _jsonResponse({'user': user.toJson()});
  }

  /// PUT `/admin/api/users/<id>`
  Future<Response> adminUpdateUser(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final name = json['name'] as String?;
    final password = json['password'] as String?;
    final isActive = json['isActive'] as bool?;

    // Hash password if provided
    String? passwordHash;
    if (password != null && password.isNotEmpty) {
      passwordHash = hashPassword(password);
    }

    final success = await metadata.updateUser(
      id,
      name: name,
      passwordHash: passwordHash,
      isActive: isActive,
    );

    if (!success) {
      return Response(404,
          body: jsonEncode({
            'error': {'code': 'not_found', 'message': 'User not found'}
          }),
          headers: {'content-type': 'application/json'});
    }

    final user = await metadata.getUser(id);
    return Response.ok(
      jsonEncode({'user': user?.toJson()}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// DELETE `/admin/api/users/<id>`
  Future<Response> adminDeleteUser(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Prevent deleting anonymous user
    if (id == User.anonymousId) {
      return Response(400,
          body: jsonEncode({
            'error': {
              'code': 'invalid_operation',
              'message': 'Cannot delete anonymous user'
            }
          }),
          headers: {'content-type': 'application/json'});
    }

    final success = await metadata.deleteUser(id);

    if (!success) {
      return Response(404,
          body: jsonEncode({
            'error': {'code': 'not_found', 'message': 'User not found'}
          }),
          headers: {'content-type': 'application/json'});
    }

    return Response.ok(
      jsonEncode({
        'success': {'message': 'User deleted successfully'}
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/users/<id>/tokens`
  Future<Response> adminListUserTokens(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Check if user exists
    final user = await metadata.getUser(id);
    if (user == null) {
      return Response(404,
          body: jsonEncode({
            'error': {'code': 'not_found', 'message': 'User not found'}
          }),
          headers: {'content-type': 'application/json'});
    }

    final tokens = await metadata.listTokens(userId: id);

    return Response.ok(
      jsonEncode({
        'tokens': tokens.map((t) => t.toJson()).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/config`
  Future<Response> adminGetAllConfig(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    try {
      // Determine actual database and storage types from runtime config
      final databaseType = config.databaseType == DatabaseType.postgresql
          ? 'postgresql'
          : 'sqlite';
      final storageType = config.useLocalStorage ? 'local' : 's3';

      // Get additional config values from database
      final allowRegistration = await metadata.getConfig('allow_registration');
      final tokenMaxTtl = await metadata.getConfig('token_max_ttl_days');
      final smtpHost = await metadata.getConfig('smtp_host');
      final smtpPort = await metadata.getConfig('smtp_port');
      final smtpFrom = await metadata.getConfig('smtp_from_address');

      // Return config as name/value pairs for the admin UI
      return Response.ok(
        jsonEncode({
          'config': [
            {
              'name': 'base_url',
              'type': 'string',
              'value': config.baseUrl,
            },
            {
              'name': 'listen_addr',
              'type': 'string',
              'value': '${config.listenAddr}:${config.listenPort}',
            },
            {
              'name': 'require_download_auth',
              'type': 'boolean',
              'value': config.requireDownloadAuth.toString(),
            },
            {
              'name': 'database_type',
              'type': 'string',
              'value': databaseType,
            },
            {
              'name': 'storage_type',
              'type': 'string',
              'value': storageType,
            },
            {
              'name': 'max_upload_size_mb',
              'type': 'number',
              'value': ((config.maxUploadSizeBytes / (1024 * 1024)).round())
                  .toString(),
            },
            {
              'name': 'allow_public_registration',
              'type': 'boolean',
              'value': (allowRegistration?.boolValue ?? true).toString(),
            },
            {
              'name': 'token_max_ttl_days',
              'type': 'number',
              'value': (tokenMaxTtl?.intValue ?? 0).toString(),
            },
            {
              'name': 'smtp_host',
              'type': 'string',
              'value': smtpHost?.stringValue ?? '',
            },
            {
              'name': 'smtp_port',
              'type': 'number',
              'value': smtpPort?.stringValue ?? '',
            },
            {
              'name': 'smtp_from',
              'type': 'string',
              'value': smtpFrom?.stringValue ?? '',
            },
          ],
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.error('Failed to get config',
          component: 'admin', error: e, stackTrace: stackTrace);
      return Response(
        500,
        body: jsonEncode({
          'error': {
            'code': 'internal_error',
            'message': 'Failed to retrieve configuration: ${e.toString()}'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// PUT `/admin/api/config/<name>`
  Future<Response> adminSetConfig(Request request, String name) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    try {
      final bodyBytes = await _readRequestBody(request);
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
      final value = body['value']?.toString();

      if (value == null) {
        return Response(
          400,
          body: jsonEncode({
            'error': {'code': 'missing_value', 'message': 'Value is required'},
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      await metadata.setConfig(name, value);

      return Response.ok(
        jsonEncode({
          'success': {'message': 'Config updated'}
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Invalid request body'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ============ Auth Handlers ============

  /// GET `/api/public-key`
  /// Returns the server's RSA public key for client-side password encryption
  Response getPublicKey(Request request) {
    return Response.ok(
      jsonEncode(passwordCrypto.getPublicKeyJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST `/api/auth/register`
  Future<Response> authRegister(Request request) async {
    // Check if registration is allowed
    final allowReg = await metadata.getConfig('allow_registration');
    if (allowReg?.boolValue == false) {
      return Response(
        403,
        body: jsonEncode({
          'error': {
            'code': 'registration_disabled',
            'message': 'Registration is disabled'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    try {
      final bodyBytes = await _readRequestBody(request);
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

      final email = body['email'] as String?;
      final encryptedPassword = body['password'] as String?;
      final name = body['name'] as String?;

      if (email == null || email.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': {'code': 'missing_email', 'message': 'Email is required'},
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Validate email format (uses pre-compiled regex for performance)
      if (!_emailRegex.hasMatch(email)) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'invalid_email',
              'message': 'Invalid email format'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Decrypt password
      if (encryptedPassword == null || encryptedPassword.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'missing_password',
              'message': 'Password is required'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      String password;
      try {
        password = passwordCrypto.decryptPassword(encryptedPassword);
      } catch (e) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'invalid_password_format',
              'message': 'Password must be encrypted with server public key'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (password.length < 8) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'weak_password',
              'message': 'Password must be at least 8 characters'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Validate password complexity (uses pre-compiled regexes for performance)
      if (!_uppercaseRegex.hasMatch(password) ||
          !_lowercaseRegex.hasMatch(password) ||
          !_digitRegex.hasMatch(password)) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'weak_password',
              'message':
                  'Password must contain uppercase, lowercase, and numbers'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if email already exists
      final existing = await metadata.getUserByEmail(email);
      if (existing != null) {
        return Response(
          409,
          body: jsonEncode({
            'error': {
              'code': 'email_exists',
              'message': 'Email already registered'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Hash password and create user
      final passwordHash = hashPassword(password);
      final userId = await metadata.createUser(
        email: email,
        passwordHash: passwordHash,
        name: name,
      );

      // Log activity
      await metadata.logActivity(
        activityType: 'user_registered',
        actorType: 'user',
        actorId: userId,
        actorEmail: email,
        targetType: 'user',
        targetId: userId,
        ipAddress: _extractClientIp(request),
      );

      // Trigger webhook (fire-and-forget with error logging)
      _triggerWebhook(
        () => webhooks.onUserRegistered(email: email),
        'user.registered',
      );

      // Send welcome email (fire-and-forget with error logging)
      _sendEmail(
        () => emails.onUserRegistered(
          email: email,
          name: name ?? '',
          baseUrl: config.baseUrl,
        ),
        'user_registered',
      );

      // Create session
      final sessionTtl = await metadata.getConfig('session_ttl_hours');
      final ttlHours = sessionTtl?.intValue ?? 24;
      final session = await metadata.createUserSession(
        userId: userId,
        ttl: Duration(hours: ttlHours),
      );

      // Get user
      final user = await metadata.getUser(userId);

      return Response.ok(
        jsonEncode({
          'user': user?.toJson(),
        }),
        headers: {
          'content-type': 'application/json',
          'set-cookie': createSessionCookie(session.sessionId,
              maxAge: Duration(hours: ttlHours)),
        },
      );
    } catch (e, stackTrace) {
      Logger.error('Registration error',
          component: 'auth', error: e, stackTrace: stackTrace);
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Invalid request body: ${e.toString()}'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST `/api/auth/login`
  Future<Response> authLogin(Request request) async {
    try {
      final bodyBytes = await _readRequestBody(request);
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

      final email = body['email'] as String?;
      final encryptedPassword = body['password'] as String?;

      if (email == null || encryptedPassword == null) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'missing_credentials',
              'message': 'Email and password are required'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Decrypt password
      String password;
      try {
        password = passwordCrypto.decryptPassword(encryptedPassword);
      } catch (e) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'invalid_password_format',
              'message': 'Password must be encrypted with server public key'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Look up user
      final user = await metadata.getUserByEmail(email);
      if (user == null || user.passwordHash == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': {
              'code': 'invalid_credentials',
              'message': 'Invalid email or password'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Verify password
      if (!verifyPassword(password, user.passwordHash!)) {
        return Response(
          401,
          body: jsonEncode({
            'error': {
              'code': 'invalid_credentials',
              'message': 'Invalid email or password'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if user is active
      if (!user.isActive) {
        return Response(
          403,
          body: jsonEncode({
            'error': {
              'code': 'user_disabled',
              'message': 'User account is disabled'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Update last login
      await metadata.touchUserLogin(user.id);

      // Create session
      final sessionTtl = await metadata.getConfig('session_ttl_hours');
      final ttlHours = sessionTtl?.intValue ?? 24;
      final session = await metadata.createUserSession(
        userId: user.id,
        ttl: Duration(hours: ttlHours),
      );

      return Response.ok(
        jsonEncode({
          'user': user.toJson(),
        }),
        headers: {
          'content-type': 'application/json',
          'set-cookie': createSessionCookie(session.sessionId,
              maxAge: Duration(hours: ttlHours)),
        },
      );
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Invalid request body'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST `/api/auth/logout`
  Future<Response> authLogout(Request request) async {
    final sessionResult = await getSession(
      request,
      lookupSession: metadata.getUserSession,
    );

    if (sessionResult is SessionValid) {
      await metadata.deleteUserSession(sessionResult.session.sessionId);
    }

    return Response.ok(
      jsonEncode({
        'success': {'message': 'Logged out'}
      }),
      headers: {
        'content-type': 'application/json',
        'set-cookie': clearSessionCookie(),
      },
    );
  }

  /// GET `/api/auth/me`
  /// Returns current user or null if not authenticated (never 401)
  Future<Response> authMe(Request request) async {
    final sessionResult = await getSession(
      request,
      lookupSession: metadata.getUserSession,
    );

    // Return null user instead of 401 for unauthenticated requests
    // This prevents console errors on public pages
    if (sessionResult is! SessionValid) {
      return Response.ok(
        jsonEncode({'user': null}),
        headers: {'content-type': 'application/json'},
      );
    }

    final user = await metadata.getUser(sessionResult.session.userId);
    if (user == null) {
      return Response.ok(
        jsonEncode({'user': null}),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({'user': user.toJson()}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// PUT `/api/auth/me`
  Future<Response> authUpdateMe(Request request) async {
    final sessionResult = await getSession(
      request,
      lookupSession: metadata.getUserSession,
    );

    if (sessionResult is! SessionValid) {
      return sessionErrorResponse(sessionResult);
    }

    try {
      final bodyBytes = await _readRequestBody(request);
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

      final name = body['name'] as String?;
      final password = body['password'] as String?;
      final currentPassword = body['currentPassword'] as String?;

      // If changing password, verify current password first
      String? passwordHash;
      if (password != null) {
        if (currentPassword == null) {
          return Response(
            400,
            body: jsonEncode({
              'error': {
                'code': 'missing_current_password',
                'message': 'Current password is required'
              },
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        final user = await metadata.getUser(sessionResult.session.userId);
        if (user?.passwordHash == null ||
            !verifyPassword(currentPassword, user!.passwordHash!)) {
          return Response(
            401,
            body: jsonEncode({
              'error': {
                'code': 'invalid_password',
                'message': 'Current password is incorrect'
              },
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        if (password.length < 8) {
          return Response(
            400,
            body: jsonEncode({
              'error': {
                'code': 'weak_password',
                'message': 'Password must be at least 8 characters'
              },
            }),
            headers: {'content-type': 'application/json'},
          );
        }

        passwordHash = hashPassword(password);
      }

      await metadata.updateUser(
        sessionResult.session.userId,
        name: name,
        passwordHash: passwordHash,
      );

      final user = await metadata.getUser(sessionResult.session.userId);

      return Response.ok(
        jsonEncode({'user': user?.toJson()}),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Invalid request body'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ============ Token Management Handlers ============

  /// GET `/api/tokens`
  Future<Response> listUserTokens(Request request) async {
    final sessionResult = await getSession(
      request,
      lookupSession: metadata.getUserSession,
    );

    if (sessionResult is! SessionValid) {
      return sessionErrorResponse(sessionResult);
    }

    final tokens =
        await metadata.listTokens(userId: sessionResult.session.userId);

    return Response.ok(
      jsonEncode({
        'tokens': tokens.map((t) => t.toJson()).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST `/api/tokens`
  Future<Response> createUserToken(Request request) async {
    final sessionResult = await getSession(
      request,
      lookupSession: metadata.getUserSession,
    );

    if (sessionResult is! SessionValid) {
      return sessionErrorResponse(sessionResult);
    }

    try {
      final bodyBytes = await _readRequestBody(request);
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

      final label = body['label'] as String?;
      final expiresInDays = body['expiresInDays'] as int?;
      final scopesRaw = body['scopes'] as List<dynamic>?;
      final scopes = scopesRaw?.cast<String>() ?? <String>[];

      if (label == null || label.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'missing_label',
              'message': 'Token label is required'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Get maximum token TTL from config
      final maxTtlConfig = await metadata.getConfig('token_max_ttl_days');
      final maxTtlDays =
          maxTtlConfig != null ? int.tryParse(maxTtlConfig.value) ?? 0 : 0;

      // Calculate effective expiration days
      int? effectiveExpiresInDays = expiresInDays;
      if (maxTtlDays > 0) {
        // Enforce maximum TTL
        if (effectiveExpiresInDays == null || effectiveExpiresInDays <= 0) {
          // If no expiration specified, use max TTL
          effectiveExpiresInDays = maxTtlDays;
        } else if (effectiveExpiresInDays > maxTtlDays) {
          // If requested expiration exceeds max, cap at max
          effectiveExpiresInDays = maxTtlDays;
        }
      }

      DateTime? expiresAt;
      if (effectiveExpiresInDays != null && effectiveExpiresInDays > 0) {
        expiresAt = DateTime.now().add(Duration(days: effectiveExpiresInDays));
      }

      final token = await metadata.createToken(
        userId: sessionResult.session.userId,
        label: label,
        scopes: scopes,
        expiresAt: expiresAt,
      );

      return Response.ok(
        jsonEncode({
          'token': token,
          'message':
              'Token created. Save this token - it will not be shown again.',
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Invalid request body'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// DELETE `/api/tokens/<label>`
  Future<Response> deleteUserToken(Request request, String label) async {
    final sessionResult = await getSession(
      request,
      lookupSession: metadata.getUserSession,
    );

    if (sessionResult is! SessionValid) {
      return sessionErrorResponse(sessionResult);
    }

    // Get all user's tokens to verify ownership
    final tokens =
        await metadata.listTokens(userId: sessionResult.session.userId);
    final token = tokens.where((t) => t.label == label).firstOrNull;

    if (token == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Token not found'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    await metadata.deleteToken(label);

    return Response.ok(
      jsonEncode({
        'success': {'message': 'Token deleted'}
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  // ============ Admin Authentication ============

  /// POST `/admin/api/auth/login` - Admin login
  Future<Response> adminLogin(Request request) async {
    // Extract IP address and user agent for logging
    final ipAddress = _extractClientIp(request) ?? 'unknown';
    final userAgent = request.headers['user-agent'];

    try {
      final bodyBytes = await _readRequestBody(request);
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

      final username = body['username'] as String?;
      final encryptedPassword = body['password'] as String?;

      if (username == null || encryptedPassword == null) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'missing_credentials',
              'message': 'Username and password are required'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Decrypt password
      String password;
      try {
        password = passwordCrypto.decryptPassword(encryptedPassword);
      } catch (e) {
        Logger.error('Password decryption failed', component: 'auth', error: e);
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'invalid_password_format',
              'message': 'Password must be encrypted with server public key'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Look up admin user
      final adminUser = await metadata.getAdminUserByUsername(username);
      if (adminUser == null || adminUser.passwordHash == null) {
        // Log failed login attempt (if user exists)
        if (adminUser != null) {
          await metadata.logAdminLogin(
            adminUserId: adminUser.id,
            ipAddress: ipAddress,
            userAgent: userAgent,
            success: false,
          );
        }
        return Response(
          401,
          body: jsonEncode({
            'error': {
              'code': 'invalid_credentials',
              'message': 'Invalid username or password'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Verify password
      if (!verifyPassword(password, adminUser.passwordHash!)) {
        // Log failed login attempt
        await metadata.logAdminLogin(
          adminUserId: adminUser.id,
          ipAddress: ipAddress,
          userAgent: userAgent,
          success: false,
        );
        return Response(
          401,
          body: jsonEncode({
            'error': {
              'code': 'invalid_credentials',
              'message': 'Invalid username or password'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Check if admin is active
      if (!adminUser.isActive) {
        // Log failed login attempt (inactive account)
        await metadata.logAdminLogin(
          adminUserId: adminUser.id,
          ipAddress: ipAddress,
          userAgent: userAgent,
          success: false,
        );
        return Response(
          403,
          body: jsonEncode({
            'error': {
              'code': 'admin_disabled',
              'message': 'Admin account is disabled'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Update last login
      await metadata.touchAdminLogin(adminUser.id);

      // Log successful login
      await metadata.logAdminLogin(
        adminUserId: adminUser.id,
        ipAddress: ipAddress,
        userAgent: userAgent,
        success: true,
      );

      // Log activity
      await metadata.logActivity(
        activityType: 'admin_login',
        actorType: 'admin',
        actorId: adminUser.id,
        actorUsername: adminUser.username,
        targetType: 'admin',
        targetId: adminUser.id,
        ipAddress: ipAddress,
      );

      // Create admin session (8-hour TTL)
      final session = await metadata.createAdminSession(
        adminUserId: adminUser.id,
        ttl: const Duration(hours: 8),
      );

      return Response.ok(
        jsonEncode({
          'adminUser': adminUser.toJson(),
        }),
        headers: {
          'content-type': 'application/json',
          'set-cookie': createAdminSessionCookie(session.sessionId,
              maxAge: const Duration(hours: 8)),
        },
      );
    } catch (e, stackTrace) {
      Logger.error('Admin login error',
          component: 'auth', error: e, stackTrace: stackTrace);
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Invalid request body: ${e.toString()}'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  /// POST `/admin/api/auth/logout` - Admin logout
  Future<Response> adminLogout(Request request) async {
    final result = await getAdminSession(
      request,
      lookupSession: metadata.getAdminSession,
    );

    // Even if session is invalid/expired, clear the cookie
    if (result is AdminSessionValid) {
      await metadata.deleteAdminSession(result.session.sessionId);
    }

    return Response.ok(
      jsonEncode({
        'success': {'message': 'Logged out'}
      }),
      headers: {
        'content-type': 'application/json',
        'set-cookie': clearAdminSessionCookie(),
      },
    );
  }

  /// GET `/admin/api/auth/me` - Get current admin user
  Future<Response> adminMe(Request request) async {
    final result = await getAdminSession(
      request,
      lookupSession: metadata.getAdminSession,
    );

    if (result is! AdminSessionValid) {
      return adminSessionErrorResponse(result);
    }

    // Get admin user
    final adminUser = await metadata.getAdminUser(result.session.userId);
    if (adminUser == null) {
      return Response(
        401,
        body: jsonEncode({
          'error': {
            'code': 'admin_not_found',
            'message': 'Admin user not found'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({'adminUser': adminUser.toJson()}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST `/admin/api/auth/change-password` - Change admin password
  Future<Response> adminChangePassword(Request request) async {
    final result = await getAdminSession(
      request,
      lookupSession: metadata.getAdminSession,
    );

    if (result is! AdminSessionValid) {
      return adminSessionErrorResponse(result);
    }

    try {
      final bodyBytes = await _readRequestBody(request);
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

      final currentPassword = body['currentPassword'] as String?;
      final newPassword = body['newPassword'] as String?;

      if (currentPassword == null || currentPassword.isEmpty) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'missing_current_password',
              'message': 'Current password is required'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      if (newPassword == null || newPassword.length < 8) {
        return Response(
          400,
          body: jsonEncode({
            'error': {
              'code': 'weak_password',
              'message': 'New password must be at least 8 characters'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Get admin user
      final adminUser = await metadata.getAdminUser(result.session.userId);
      if (adminUser == null || adminUser.passwordHash == null) {
        return Response(
          401,
          body: jsonEncode({
            'error': {
              'code': 'admin_not_found',
              'message': 'Admin user not found'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Verify current password
      if (!verifyPassword(currentPassword, adminUser.passwordHash!)) {
        return Response(
          401,
          body: jsonEncode({
            'error': {
              'code': 'invalid_password',
              'message': 'Current password is incorrect'
            },
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      // Update password and clear mustChangePassword flag
      final newPasswordHash = hashPassword(newPassword);
      await metadata.updateAdminUser(
        adminUser.id,
        passwordHash: newPasswordHash,
        mustChangePassword: false,
      );

      // Get updated admin user
      final updatedAdmin = await metadata.getAdminUser(adminUser.id);

      return Response.ok(
        jsonEncode({
          'success': {'message': 'Password changed successfully'},
          'admin': updatedAdmin?.toJson(),
        }),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Invalid request body'
          },
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  // ============ Admin User Management ============

  /// GET `/admin/api/admin-users` - List all admin users
  Future<Response> adminListAdminUsers(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final page = (int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1)
        .clamp(1, 10000);
    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20)
            .clamp(1, 100);

    final adminUsers = await metadata.listAdminUsers(page: page, limit: limit);

    return Response.ok(
      jsonEncode({
        'adminUsers': adminUsers.map((u) => u.toJson()).toList(),
        'page': page,
        'limit': limit,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/admin-users/<id>` - Get specific admin user with summary
  Future<Response> adminGetAdminUser(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final adminUser = await metadata.getAdminUser(id);
    if (adminUser == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Admin user not found'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Get recent login history (last 10 entries)
    final recentLogins =
        await metadata.getAdminLoginHistory(adminUserId: id, limit: 10);

    return Response.ok(
      jsonEncode({
        'adminUser': adminUser.toJson(),
        'recentLogins': recentLogins.map((l) => l.toJson()).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/admin-users/<id>/login-history` - Get login history for admin user
  Future<Response> adminGetLoginHistory(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    // Verify admin user exists
    final adminUser = await metadata.getAdminUser(id);
    if (adminUser == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Admin user not found'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final limit =
        (int.tryParse(request.url.queryParameters['limit'] ?? '50') ?? 50)
            .clamp(1, 200);

    final loginHistory = await metadata.getAdminLoginHistory(
      adminUserId: id,
      limit: limit,
    );

    return Response.ok(
      jsonEncode({
        'adminUser': adminUser.toJson(),
        'loginHistory': loginHistory.map((l) => l.toJson()).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/health/detailed` - Detailed health check with database status
  Future<Response> detailedHealthCheck(Request request) async {
    final startTime = DateTime.now();

    // Get database health
    final dbHealth = await metadata.healthCheck();

    // Get blob storage health (check if accessible)
    Map<String, dynamic> storageHealth;
    final storageType = config.useLocalStorage ? 'local' : 's3';
    try {
      // Just checking if the storage is accessible
      storageHealth = {
        'status': 'healthy',
        'type': storageType,
      };
    } catch (e) {
      Logger.warn('Storage health check failed', component: 'health', error: e);
      storageHealth = {
        'status': 'unhealthy',
        'type': storageType,
        'error': e.toString(),
      };
    }

    final endTime = DateTime.now();
    final totalLatencyMs =
        endTime.difference(startTime).inMicroseconds / 1000.0;

    // Overall status is unhealthy if any component is unhealthy
    final overallStatus =
        dbHealth['status'] == 'healthy' && storageHealth['status'] == 'healthy'
            ? 'healthy'
            : 'unhealthy';

    return Response.ok(
      jsonEncode({
        'status': overallStatus,
        'totalLatencyMs': totalLatencyMs,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'version': Platform.environment['REPUB_VERSION'] ?? 'unknown',
        'components': {
          'database': dbHealth,
          'storage': storageHealth,
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/metrics` - Prometheus metrics endpoint
  Future<Response> prometheusMetrics(Request request) async {
    final dbHealth = await metadata.healthCheck();

    // Get stats for metrics
    final stats = await metadata.getAdminStats();
    final userCount = await metadata.countUsers();
    final tokenCount = await metadata.countActiveTokens();
    final downloadCount = await metadata.getTotalDownloads();

    final buffer = StringBuffer();

    // Help and type comments
    buffer.writeln('# HELP repub_up Server availability (1 = up, 0 = down)');
    buffer.writeln('# TYPE repub_up gauge');
    buffer.writeln('repub_up ${dbHealth['status'] == 'healthy' ? 1 : 0}');

    buffer.writeln();
    buffer.writeln('# HELP repub_packages_total Total number of packages');
    buffer.writeln('# TYPE repub_packages_total gauge');
    buffer.writeln('repub_packages_total{type="local"} ${stats.localPackages}');
    buffer
        .writeln('repub_packages_total{type="cached"} ${stats.cachedPackages}');

    buffer.writeln();
    buffer.writeln(
        '# HELP repub_versions_total Total number of package versions');
    buffer.writeln('# TYPE repub_versions_total gauge');
    buffer.writeln('repub_versions_total ${stats.totalVersions}');

    buffer.writeln();
    buffer.writeln('# HELP repub_users_total Total number of users');
    buffer.writeln('# TYPE repub_users_total gauge');
    buffer.writeln('repub_users_total $userCount');

    buffer.writeln();
    buffer.writeln('# HELP repub_tokens_active Number of active tokens');
    buffer.writeln('# TYPE repub_tokens_active gauge');
    buffer.writeln('repub_tokens_active $tokenCount');

    buffer.writeln();
    buffer.writeln('# HELP repub_downloads_total Total number of downloads');
    buffer.writeln('# TYPE repub_downloads_total counter');
    buffer.writeln('repub_downloads_total $downloadCount');

    if (dbHealth['dbSizeBytes'] != null) {
      buffer.writeln();
      buffer.writeln(
          '# HELP repub_database_size_bytes Size of the database in bytes');
      buffer.writeln('# TYPE repub_database_size_bytes gauge');
      buffer.writeln('repub_database_size_bytes ${dbHealth['dbSizeBytes']}');
    }

    if (dbHealth['latencyMs'] != null) {
      buffer.writeln();
      buffer.writeln(
          '# HELP repub_database_latency_ms Database query latency in milliseconds');
      buffer.writeln('# TYPE repub_database_latency_ms gauge');
      buffer.writeln('repub_database_latency_ms ${dbHealth['latencyMs']}');
    }

    return Response.ok(
      buffer.toString(),
      headers: {'content-type': 'text/plain; version=0.0.4; charset=utf-8'},
    );
  }

  // ============ Feed Endpoints ============

  /// GET `/feed.rss` - Global RSS feed for recent package updates.
  Future<Response> globalRssFeed(Request request) async {
    final result = await metadata.listPackages(page: 1, limit: 100);

    final feed = FeedGenerator(
      baseUrl: config.baseUrl,
      title: 'Package Updates',
      description: 'Recent package updates and releases',
    );

    final rss = feed.generateRss(result.packages, limit: 20);

    return Response.ok(
      rss,
      headers: {
        'content-type': 'application/rss+xml; charset=utf-8',
        'cache-control': 'public, max-age=300', // Cache for 5 minutes
      },
    );
  }

  /// GET `/feed.atom` - Global Atom feed for recent package updates.
  Future<Response> globalAtomFeed(Request request) async {
    final result = await metadata.listPackages(page: 1, limit: 100);

    final feed = FeedGenerator(
      baseUrl: config.baseUrl,
      title: 'Package Updates',
      description: 'Recent package updates and releases',
    );

    final atom = feed.generateAtom(result.packages, limit: 20);

    return Response.ok(
      atom,
      headers: {
        'content-type': 'application/atom+xml; charset=utf-8',
        'cache-control': 'public, max-age=300', // Cache for 5 minutes
      },
    );
  }

  /// GET `/packages/<name>/feed.rss` - RSS feed for a specific package.
  Future<Response> packageRssFeed(Request request, String name) async {
    final pkg = await metadata.getPackageInfo(name);
    if (pkg == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Package not found'}
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final feed = FeedGenerator(baseUrl: config.baseUrl);
    final rss = feed.generatePackageRss(pkg);

    return Response.ok(
      rss,
      headers: {
        'content-type': 'application/rss+xml; charset=utf-8',
        'cache-control': 'public, max-age=300', // Cache for 5 minutes
      },
    );
  }

  /// GET `/packages/<name>/feed.atom` - Atom feed for a specific package.
  Future<Response> packageAtomFeed(Request request, String name) async {
    final pkg = await metadata.getPackageInfo(name);
    if (pkg == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Package not found'}
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final feed = FeedGenerator(baseUrl: config.baseUrl);
    final atom = feed.generatePackageAtom(pkg);

    return Response.ok(
      atom,
      headers: {
        'content-type': 'application/atom+xml; charset=utf-8',
        'cache-control': 'public, max-age=300', // Cache for 5 minutes
      },
    );
  }

  // ============ Webhook Admin Endpoints ============

  /// GET `/admin/api/webhooks` - List all webhooks.
  Future<Response> adminListWebhooks(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final activeOnly = request.url.queryParameters['active_only'] == 'true';
    final webhooks = await metadata.listWebhooks(activeOnly: activeOnly);

    return Response.ok(
      jsonEncode({
        'webhooks': webhooks.map((w) => w.toJson()).toList(),
        'total': webhooks.length,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST `/admin/api/webhooks` - Create a new webhook.
  Future<Response> adminCreateWebhook(Request request) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final url = body['url'] as String?;
      final secret = body['secret'] as String?;
      final events = (body['events'] as List?)?.cast<String>() ?? ['*'];

      if (url == null || url.isEmpty) {
        return Response(
          400,
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'error': {'code': 'invalid_request', 'message': 'URL is required'},
          }),
        );
      }

      // Validate URL and check for SSRF
      final urlValidation = _validateWebhookUrl(url);
      if (urlValidation != null) {
        return urlValidation;
      }

      // Validate events
      for (final event in events) {
        if (!WebhookEventType.isValid(event)) {
          return Response(
            400,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'error': {
                'code': 'invalid_event',
                'message':
                    'Invalid event type: $event. Valid types are: ${WebhookEventType.all.join(', ')} or *',
              },
            }),
          );
        }
      }

      final webhook = await metadata.createWebhook(
        url: url,
        secret: secret,
        events: events,
      );

      // Log activity
      final admin = await _getAdminFromSession(request);
      await metadata.logActivity(
        activityType: 'webhook_created',
        actorType: 'admin',
        actorId: admin?.id,
        actorUsername: admin?.username,
        targetType: 'webhook',
        targetId: webhook.id,
        ipAddress:
            request.headers['x-forwarded-for'] ?? request.headers['x-real-ip'],
      );

      return Response.ok(
        jsonEncode(webhook.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response(
        400,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Invalid request body'
          },
        }),
      );
    }
  }

  /// GET `/admin/api/webhooks/<id>` - Get a webhook by ID.
  Future<Response> adminGetWebhook(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final webhook = await metadata.getWebhook(id);
    if (webhook == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Webhook not found'}
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode(webhook.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  /// PUT `/admin/api/webhooks/<id>` - Update a webhook.
  Future<Response> adminUpdateWebhook(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final webhook = await metadata.getWebhook(id);
    if (webhook == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Webhook not found'}
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;

      // Validate URL if provided
      final newUrl = body['url'] as String?;
      if (newUrl != null && newUrl != webhook.url) {
        final urlValidation = _validateWebhookUrl(newUrl);
        if (urlValidation != null) {
          return urlValidation;
        }
      }

      final updated = webhook.copyWith(
        url: body['url'] as String? ?? webhook.url,
        secret: body['secret'] as String?,
        events: (body['events'] as List?)?.cast<String>(),
        isActive: body['is_active'] as bool?,
      );

      await metadata.updateWebhook(updated);

      return Response.ok(
        jsonEncode(updated.toJson()),
        headers: {'content-type': 'application/json'},
      );
    } catch (e) {
      return Response(
        400,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {
            'code': 'invalid_request',
            'message': 'Invalid request body'
          },
        }),
      );
    }
  }

  /// DELETE `/admin/api/webhooks/<id>` - Delete a webhook.
  Future<Response> adminDeleteWebhook(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final webhook = await metadata.getWebhook(id);
    if (webhook == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Webhook not found'}
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    await metadata.deleteWebhook(id);

    // Log activity
    final admin = await _getAdminFromSession(request);
    await metadata.logActivity(
      activityType: 'webhook_deleted',
      actorType: 'admin',
      actorId: admin?.id,
      actorUsername: admin?.username,
      targetType: 'webhook',
      targetId: id,
      ipAddress:
          request.headers['x-forwarded-for'] ?? request.headers['x-real-ip'],
    );

    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/webhooks/<id>/deliveries` - Get recent deliveries for a webhook.
  Future<Response> adminGetWebhookDeliveries(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final webhook = await metadata.getWebhook(id);
    if (webhook == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Webhook not found'}
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;
    final deliveries = await metadata.getWebhookDeliveries(id, limit: limit);

    return Response.ok(
      jsonEncode({
        'deliveries': deliveries.map((d) => d.toJson()).toList(),
        'total': deliveries.length,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// POST `/admin/api/webhooks/<id>/test` - Send a test event to a webhook.
  Future<Response> adminTestWebhook(Request request, String id) async {
    final authError = await _requireAdminAuth(request);
    if (authError != null) return authError;

    final webhook = await metadata.getWebhook(id);
    if (webhook == null) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Webhook not found'}
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    // Send a test ping event
    await webhooks.triggerEvent(
      eventType: 'test.ping',
      data: {
        'webhook_id': id,
        'message': 'This is a test webhook delivery',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    return Response.ok(
      jsonEncode({
        'success': true,
        'message': 'Test webhook sent. Check deliveries for result.',
      }),
      headers: {'content-type': 'application/json'},
    );
  }
}
