import 'dart:convert';
import 'dart:typed_data';

import 'package:repub_auth/repub_auth.dart';
import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'publish.dart';

/// Create the API router.
Router createRouter({
  required Config config,
  required MetadataStore metadata,
  required BlobStore blobs,
}) {
  final router = Router();
  final handlers = ApiHandlers(config: config, metadata: metadata, blobs: blobs);

  // Package info endpoint
  router.get('/api/packages/<name>', handlers.getPackage);

  // Publish flow
  router.get('/api/packages/versions/new', handlers.initiateUpload);
  router.post('/api/packages/versions/upload/<sessionId>', handlers.uploadPackage);
  router.get('/api/packages/versions/finalize/<sessionId>', handlers.finalizeUpload);

  // Download endpoint (legacy format)
  router.get('/packages/<name>/versions/<version>.tar.gz', handlers.downloadPackage);

  // Health check
  router.get('/health', (Request req) {
    return Response.ok(jsonEncode({'status': 'ok'}),
        headers: {'content-type': 'application/json'});
  });

  return router;
}

/// API handler implementations.
class ApiHandlers {
  final Config config;
  final MetadataStore metadata;
  final BlobStore blobs;

  // In-memory storage for upload data (sessionId -> bytes)
  final Map<String, Uint8List> _uploadData = {};

  ApiHandlers({
    required this.config,
    required this.metadata,
    required this.blobs,
  });

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
      final archiveUrl = '${config.baseUrl}/packages/${v.packageName}/versions/${v.version}.tar.gz';
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
      if (info.package.replacedBy != null) 'replacedBy': info.package.replacedBy,
    };

    return Response.ok(
      jsonEncode(response),
      headers: {'content-type': 'application/json'},
    );
  }

  /// GET /api/packages/versions/new
  Future<Response> initiateUpload(Request request) async {
    // Require authentication
    final authResult = await authenticate(
      request,
      lookupToken: metadata.getTokenByHash,
      touchToken: metadata.touchToken,
    );
    if (authResult is! AuthSuccess) {
      return _authErrorResponse(authResult);
    }

    // Create upload session
    final session = await metadata.createUploadSession();

    final uploadUrl = '${config.baseUrl}/api/packages/versions/upload/${session.id}';

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
    // Require authentication
    final authResult = await authenticate(
      request,
      lookupToken: metadata.getTokenByHash,
      touchToken: metadata.touchToken,
    );
    if (authResult is! AuthSuccess) {
      return _authErrorResponse(authResult);
    }

    // Validate session
    final session = await metadata.getUploadSession(sessionId);
    if (session == null) {
      return Response(
        400,
        body: jsonEncode({
          'error': {'code': 'invalid_session', 'message': 'Invalid or expired upload session'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }

    if (session.isExpired) {
      return Response(
        400,
        body: jsonEncode({
          'error': {'code': 'expired_session', 'message': 'Upload session has expired'},
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
    final finalizeUrl = '${config.baseUrl}/api/packages/versions/finalize/$sessionId';
    return Response(
      204,
      headers: {'location': finalizeUrl},
    );
  }

  /// GET `/api/packages/versions/finalize/<sessionId>`
  Future<Response> finalizeUpload(Request request, String sessionId) async {
    // Require authentication
    final authResult = await authenticate(
      request,
      lookupToken: metadata.getTokenByHash,
      touchToken: metadata.touchToken,
    );
    if (authResult is! AuthSuccess) {
      return _authErrorResponse(authResult);
    }

    final token = authResult.token;

    // Get upload data
    final tarballBytes = _uploadData[sessionId];
    if (tarballBytes == null) {
      return Response(
        400,
        body: jsonEncode({
          'error': {'code': 'no_upload', 'message': 'No upload data found for session'},
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
          'error': {'code': 'invalid_session', 'message': 'Invalid or expired upload session'},
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

    // Check publish permission
    if (!token.canPublish(success.packageName)) {
      _uploadData.remove(sessionId);
      return forbidden('Not authorized to publish package: ${success.packageName}');
    }

    // Check if version already exists
    if (await metadata.versionExists(success.packageName, success.version)) {
      _uploadData.remove(sessionId);
      return Response(
        400,
        body: jsonEncode({
          'error': {
            'code': 'version_exists',
            'message': 'Version ${success.version} of ${success.packageName} already exists',
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
          'message': 'Successfully published ${success.packageName} ${success.version}',
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

    // Get version info
    final versionInfo = await metadata.getPackageVersion(name, version);
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

    try {
      final bytes = await blobs.getArchive(versionInfo.archiveKey);
      return Response.ok(
        bytes,
        headers: {
          'content-type': 'application/gzip',
          'content-length': bytes.length.toString(),
        },
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({
          'error': {'code': 'storage_error', 'message': 'Failed to retrieve archive'},
        }),
        headers: {'content-type': 'application/json'},
      );
    }
  }

  Future<Uint8List> _parseMultipartUpload(Request request) async {
    final contentType = request.headers['content-type'] ?? '';
    final boundaryMatch = RegExp(r'boundary=(.+)$').firstMatch(contentType);
    if (boundaryMatch == null) {
      return Uint8List(0);
    }

    final boundary = boundaryMatch.group(1)!;
    final bytes = await request.read().expand((x) => x).toList();
    final body = Uint8List.fromList(bytes);

    final bodyStr = utf8.decode(body, allowMalformed: true);
    final parts = bodyStr.split('--$boundary');

    for (final part in parts) {
      if (part.contains('filename=') || part.contains('name="file"')) {
        final headerEnd = part.indexOf('\r\n\r\n');
        if (headerEnd == -1) continue;

        final contentStart = headerEnd + 4;
        final contentEnd = part.lastIndexOf('\r\n');
        if (contentEnd <= contentStart) continue;

        final partStartInBody = bodyStr.indexOf(part);
        final start = partStartInBody + contentStart;
        final end = partStartInBody + contentEnd;

        if (start >= 0 && end <= body.length && start < end) {
          return Uint8List.sublistView(body, start, end);
        }
      }
    }

    return Uint8List(0);
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
}
