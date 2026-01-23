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

import 'publish.dart';
import 'upstream.dart';

/// Create the API router.
/// Set [serveStaticFiles] to false in dev mode to use webdev proxy instead.
Router createRouter({
  required Config config,
  required MetadataStore metadata,
  required BlobStore blobs,
  required BlobStore cacheBlobs,
  bool serveStaticFiles = true,
}) {
  final router = Router();
  final handlers = ApiHandlers(
      config: config, metadata: metadata, blobs: blobs, cacheBlobs: cacheBlobs);

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

  // Health check
  router.get('/health', (Request req) {
    return Response.ok(jsonEncode({'status': 'ok'}),
        headers: {'content-type': 'application/json'});
  });

  // Admin endpoints (external ACL protected)
  router.get('/admin/api/stats', handlers.adminGetStats);
  router.get('/admin/api/packages/local', handlers.adminListLocalPackages);
  router.get('/admin/api/packages/cached', handlers.adminListCachedPackages);
  router.delete('/admin/api/packages/<name>', handlers.adminDeletePackage);
  router.delete('/admin/api/packages/<name>/versions/<version>',
      handlers.adminDeletePackageVersion);
  router.post('/admin/api/packages/<name>/discontinue',
      handlers.adminDiscontinuePackage);
  router.delete('/admin/api/cache', handlers.adminClearCache);
  router.get('/admin/api/users', handlers.adminListUsers);
  router.get('/admin/api/config', handlers.adminGetAllConfig);
  router.put('/admin/api/config/<name>', handlers.adminSetConfig);

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
        // Check if it's an API route first
        if (path.startsWith('api/') || path.startsWith('packages/')) {
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
      print('Serving web UI from: ${dir.absolute.path}');
      return path;
    }
  }

  print('Web UI not found - run "melos run build:web" to build it');
  return null;
}

/// API handler implementations.
class ApiHandlers {
  final Config config;
  final MetadataStore metadata;
  final BlobStore blobs;
  final BlobStore cacheBlobs;

  // In-memory storage for upload data (sessionId -> bytes)
  final Map<String, Uint8List> _uploadData = {};

  // Upstream client for caching proxy
  UpstreamClient? _upstream;

  ApiHandlers({
    required this.config,
    required this.metadata,
    required this.blobs,
    required this.cacheBlobs,
  });

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
    }

    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

    final result =
        await metadata.listPackages(page: page, limit: limit.clamp(1, 100));

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

    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

    final result = await metadata.searchPackages(query,
        page: page, limit: limit.clamp(1, 100));

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

    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

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
      final namesToFetch = packageNames.take(limit.clamp(1, 100)).toList();
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
    } catch (e) {
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
    } catch (e) {
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
      final bytes = await request.read().expand((x) => x).toList();
      tarballBytes = Uint8List.fromList(bytes);
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

    // Store temporarily
    _uploadData[sessionId] = tarballBytes;

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
      return Response(
        400,
        body: jsonEncode({
          'error': {'code': 'validation_error', 'message': result.message},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final success = result as PublishSuccess;

    // Determine the user ID for ownership
    final userId = token?.userId ?? User.anonymousId;

    // Check publish permission based on package ownership
    final existingPackage = await metadata.getPackage(success.packageName);
    if (existingPackage != null && !existingPackage.canPublish(userId)) {
      _uploadData.remove(sessionId);
      return forbidden(
          'Not authorized to publish package: ${success.packageName}');
    }

    // Check if version already exists
    if (await metadata.versionExists(success.packageName, success.version)) {
      _uploadData.remove(sessionId);
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

    // Clean up
    _uploadData.remove(sessionId);

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
        return Response.ok(
          Stream.value(bytes),
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': bytes.length.toString(),
          },
        );
      } catch (e) {
        // If storage fails, try upstream
        print('Storage error for $name@$version: $e');
      }
    }

    // Try to fetch from upstream and cache
    if (upstream != null) {
      final upstreamVersion = await upstream!.getVersion(name, version);
      if (upstreamVersion != null && upstreamVersion.archiveUrl.isNotEmpty) {
        print(
            'Fetching $name@$version from upstream: ${upstreamVersion.archiveUrl}');
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

            print('Cached $name@$version from upstream');

            return Response.ok(
              Stream.value(archiveBytes),
              headers: {
                'content-type': 'application/octet-stream',
                'content-length': archiveBytes.length.toString(),
              },
            );
          } catch (e) {
            print('Failed to cache $name@$version: $e');
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
    final bytes = await request.read().expand((x) => x).toList();
    final body = Uint8List.fromList(bytes);

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
    final stats = await metadata.getAdminStats();

    return Response.ok(
      jsonEncode(stats.toJson()),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/api/admin/packages/local`
  Future<Response> adminListLocalPackages(Request request) async {
    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

    final result = await metadata.listPackagesByType(
      isUpstreamCache: false,
      page: page,
      limit: limit.clamp(1, 100),
    );

    return Response.ok(
      jsonEncode(result.toJson(config.baseUrl)),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/api/admin/packages/cached`
  Future<Response> adminListCachedPackages(Request request) async {
    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

    final result = await metadata.listPackagesByType(
      isUpstreamCache: true,
      page: page,
      limit: limit.clamp(1, 100),
    );

    return Response.ok(
      jsonEncode(result.toJson(config.baseUrl)),
      headers: {'content-type': 'application/json'},
    );
  }

  /// DELETE `/api/admin/packages/<name>`
  Future<Response> adminDeletePackage(Request request, String name) async {
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
        print('Warning: Failed to delete blob $key: $e');
      }
    }

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
        print('Warning: Failed to delete blob $archiveKey: $e');
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

  /// POST `/api/admin/packages/<name>/discontinue`
  Future<Response> adminDiscontinuePackage(Request request, String name) async {
    // Parse body for optional replacedBy
    String? replacedBy;
    try {
      final bodyBytes = await request.read().expand((x) => x).toList();
      if (bodyBytes.isNotEmpty) {
        final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;
        replacedBy = body['replacedBy'] as String?;
      }
    } catch (_) {
      // Ignore body parsing errors
    }

    final success =
        await metadata.discontinuePackage(name, replacedBy: replacedBy);

    if (!success) {
      return Response.notFound(
        jsonEncode({
          'error': {'code': 'not_found', 'message': 'Package not found: $name'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({
        'success': {
          'message': 'Package $name marked as discontinued',
          if (replacedBy != null) 'replacedBy': replacedBy,
        },
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// DELETE `/api/admin/cache`
  Future<Response> adminClearCache(Request request) async {
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
        print('Warning: Failed to delete cached blob $key: $e');
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
    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final limit =
        int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

    final users =
        await metadata.listUsers(page: page, limit: limit.clamp(1, 100));

    return Response.ok(
      jsonEncode({
        'users': users.map((u) => u.toJson()).toList(),
        'page': page,
        'limit': limit,
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET `/admin/api/config`
  Future<Response> adminGetAllConfig(Request request) async {
    final configs = await metadata.getAllConfig();

    return Response.ok(
      jsonEncode({
        'config': configs.map((c) => c.toJson()).toList(),
      }),
      headers: {'content-type': 'application/json'},
    );
  }

  /// PUT `/admin/api/config/<name>`
  Future<Response> adminSetConfig(Request request, String name) async {
    try {
      final bodyBytes = await request.read().expand((x) => x).toList();
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
      final bodyBytes = await request.read().expand((x) => x).toList();
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

      final email = body['email'] as String?;
      final password = body['password'] as String?;
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

      if (password == null || password.length < 8) {
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

  /// POST `/api/auth/login`
  Future<Response> authLogin(Request request) async {
    try {
      final bodyBytes = await request.read().expand((x) => x).toList();
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

      final email = body['email'] as String?;
      final password = body['password'] as String?;

      if (email == null || password == null) {
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
      final bodyBytes = await request.read().expand((x) => x).toList();
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
      final bodyBytes = await request.read().expand((x) => x).toList();
      final body = jsonDecode(utf8.decode(bodyBytes)) as Map<String, dynamic>;

      final label = body['label'] as String?;
      final expiresInDays = body['expiresInDays'] as int?;

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

      DateTime? expiresAt;
      if (expiresInDays != null && expiresInDays > 0) {
        expiresAt = DateTime.now().add(Duration(days: expiresInDays));
      }

      final token = await metadata.createToken(
        userId: sessionResult.session.userId,
        label: label,
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
}
