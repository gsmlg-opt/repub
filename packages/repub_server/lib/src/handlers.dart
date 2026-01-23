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
Router createRouter({
  required Config config,
  required MetadataStore metadata,
  required BlobStore blobs,
}) {
  final router = Router();
  final handlers =
      ApiHandlers(config: config, metadata: metadata, blobs: blobs);

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

  // Admin endpoints (require admin scope)
  router.get('/api/admin/stats', handlers.adminGetStats);
  router.get('/api/admin/packages/local', handlers.adminListLocalPackages);
  router.get('/api/admin/packages/cached', handlers.adminListCachedPackages);
  router.delete('/api/admin/packages/<name>', handlers.adminDeletePackage);
  router.delete('/api/admin/packages/<name>/versions/<version>',
      handlers.adminDeletePackageVersion);
  router.post('/api/admin/packages/<name>/discontinue',
      handlers.adminDiscontinuePackage);
  router.delete('/api/admin/cache', handlers.adminClearCache);

  // Web UI static files - serve from web build directory
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

  // In-memory storage for upload data (sessionId -> bytes)
  final Map<String, Uint8List> _uploadData = {};

  // Upstream client for caching proxy
  UpstreamClient? _upstream;

  ApiHandlers({
    required this.config,
    required this.metadata,
    required this.blobs,
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
        requiredScope: 'read:all',
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }
    }

    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

    final result = await metadata.listPackages(page: page, limit: limit.clamp(1, 100));

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
        requiredScope: 'read:all',
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
          'error': {'code': 'missing_query', 'message': 'Search query is required'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

    final result = await metadata.searchPackages(query, page: page, limit: limit.clamp(1, 100));

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
          'error': {'code': 'upstream_disabled', 'message': 'Upstream proxy is not enabled'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final query = request.url.queryParameters['q'] ?? '';
    if (query.isEmpty) {
      return Response(
        400,
        body: jsonEncode({
          'error': {'code': 'missing_query', 'message': 'Search query is required'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    final page = int.tryParse(request.url.queryParameters['page'] ?? '1') ?? 1;
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

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

      // Fetch full package info for the first 'limit' results
      final upstreamInfos = <PackageInfo>[];
      for (final name in packageNames.take(limit.clamp(1, 100))) {
        final upstreamPkg = await upstream!.getPackage(name);
        if (upstreamPkg != null) {
          upstreamInfos.add(PackageInfo(
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
          ));
        }
      }

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
          'error': {'code': 'upstream_error', 'message': 'Failed to search upstream: $e'},
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
          'error': {'code': 'upstream_disabled', 'message': 'Upstream proxy is not enabled'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    try {
      final upstreamPkg = await upstream!.getPackage(name);

      if (upstreamPkg == null) {
        return Response.notFound(
          jsonEncode({
            'error': {'code': 'not_found', 'message': 'Package not found on upstream'},
          }),
          headers: {'content-type': 'application/json'},
        );
      }

      return _buildUpstreamPackageResponse(upstreamPkg);
    } catch (e) {
      return Response(
        500,
        body: jsonEncode({
          'error': {'code': 'upstream_error', 'message': 'Failed to fetch upstream package: $e'},
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
        requiredScope: 'read:all',
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
        requiredScope: 'read:all',
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

    // Check publish permission (only if auth is required)
    if (token != null && !token.canPublish(success.packageName)) {
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

    // Store metadata
    await metadata.upsertPackageVersion(
      packageName: success.packageName,
      version: success.version,
      pubspec: success.pubspec,
      archiveKey: archiveKey,
      archiveSha256: success.sha256Hash,
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
        requiredScope: 'read:all',
      );
      if (authResult is! AuthSuccess) {
        return _authErrorResponse(authResult);
      }
    }

    // Get version info from local storage
    final versionInfo = await metadata.getPackageVersion(name, version);

    // If found locally, serve from local storage
    if (versionInfo != null) {
      try {
        final bytes = await blobs.getArchive(versionInfo.archiveKey);
        return Response.ok(
          Stream.value(bytes),
          headers: {
            'content-type': 'application/octet-stream',
            'content-length': bytes.length.toString(),
          },
        );
      } catch (e) {
        // If local storage fails, try upstream
        print('Local storage error for $name@$version: $e');
      }
    }

    // Try to fetch from upstream and cache
    if (upstream != null) {
      final upstreamVersion = await upstream!.getVersion(name, version);
      if (upstreamVersion != null && upstreamVersion.archiveUrl.isNotEmpty) {
        print('Fetching $name@$version from upstream: ${upstreamVersion.archiveUrl}');
        final archiveBytes = await upstream!.downloadArchive(upstreamVersion.archiveUrl);

        if (archiveBytes != null) {
          // Cache the archive
          try {
            final sha256Hash = sha256.convert(archiveBytes).toString();
            final archiveKey = blobs.archiveKey(name, version, sha256Hash);

            // Store to blob storage
            await blobs.putArchive(key: archiveKey, data: archiveBytes);

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
        if (latest.archiveSha256 != null) 'archive_sha256': latest.archiveSha256,
        if (latest.published != null) 'published': latest.published!.toIso8601String(),
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
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

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
    final limit = int.tryParse(request.url.queryParameters['limit'] ?? '20') ?? 20;

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

    // Delete blobs
    for (final key in archiveKeys) {
      try {
        await blobs.delete(key);
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

    // Delete blob
    if (archiveKey != null) {
      try {
        await blobs.delete(archiveKey);
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

    final success = await metadata.discontinuePackage(name, replacedBy: replacedBy);

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

    // Delete blobs
    var blobsDeleted = 0;
    for (final key in allArchiveKeys) {
      try {
        await blobs.delete(key);
        blobsDeleted++;
      } catch (e) {
        print('Warning: Failed to delete blob $key: $e');
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
}
