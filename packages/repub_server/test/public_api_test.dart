import 'dart:convert';
import 'dart:io';

import 'package:repub_model/repub_model.dart';
import 'package:repub_server/src/handlers.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('Public API Tests', () {
    late SqliteMetadataStore metadata;
    late BlobStore blobs;
    late BlobStore cacheBlobs;
    late Config config;
    late ApiHandlers handlers;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('repub_public_api_test_');

      metadata = SqliteMetadataStore.inMemory();
      await metadata.runMigrations();

      blobs = FileBlobStore(
        basePath: '${tempDir.path}/storage',
        baseUrl: 'http://localhost:4920',
      );
      cacheBlobs = FileBlobStore(
        basePath: '${tempDir.path}/cache',
        baseUrl: 'http://localhost:4920',
        isCache: true,
      );

      config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite::memory:',
        storagePath: '${tempDir.path}/storage',
        requirePublishAuth: true,
        requireDownloadAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: false,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      handlers = ApiHandlers(
        config: config,
        metadata: metadata,
        blobs: blobs,
        cacheBlobs: cacheBlobs,
      );
    });

    tearDown(() async {
      await metadata.close();
      await tempDir.delete(recursive: true);
    });

    group('GET /api/packages (listPackages)', () {
      test('returns empty list when no packages exist', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['packages'], isA<List>());
        expect((body['packages'] as List).isEmpty, isTrue);
        expect(body['total'], equals(0));
      });

      test('returns packages when they exist', () async {
        // Create some packages
        await metadata.upsertPackageVersion(
          packageName: 'test_package',
          version: '1.0.0',
          pubspec: {'name': 'test_package', 'version': '1.0.0'},
          archiveKey: 'test_package/1.0.0.tar.gz',
          archiveSha256: 'abc123',
        );

        await metadata.upsertPackageVersion(
          packageName: 'another_package',
          version: '2.0.0',
          pubspec: {'name': 'another_package', 'version': '2.0.0'},
          archiveKey: 'another_package/2.0.0.tar.gz',
          archiveSha256: 'def456',
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        final packages = body['packages'] as List;
        expect(packages.length, equals(2));
        expect(body['total'], equals(2));
      });

      test('supports pagination', () async {
        // Create 5 packages
        for (var i = 0; i < 5; i++) {
          await metadata.upsertPackageVersion(
            packageName: 'pkg_$i',
            version: '1.0.0',
            pubspec: {'name': 'pkg_$i', 'version': '1.0.0'},
            archiveKey: 'pkg_$i/1.0.0.tar.gz',
            archiveSha256: 'hash$i',
          );
        }

        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages?page=1&limit=2'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        final packages = body['packages'] as List;
        expect(packages.length, equals(2));
        expect(body['total'], equals(5));
        expect(body['page'], equals(1));
        expect(body['limit'], equals(2));
      });

      test('clamps limit to maximum 100', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages?limit=500'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        // Limit should be clamped to 100
        expect(body['limit'], lessThanOrEqualTo(100));
      });

      test('handles invalid page parameter gracefully', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages?page=invalid'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));

        // Should default to page 1
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['page'], equals(1));
      });

      test('clamps negative page to 1', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages?page=-5'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));

        // Negative page should be clamped to 1
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['page'], equals(1));
      });

      test('clamps zero page to 1', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages?page=0'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));

        // Zero page should be clamped to 1
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['page'], equals(1));
      });

      test('clamps negative limit to 1', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages?limit=-10'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));

        // Negative limit should be clamped to 1
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['limit'], equals(1));
      });

      test('clamps page to maximum 10000', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages?page=999999'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));

        // Extremely high page should be clamped
        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['page'], lessThanOrEqualTo(10000));
      });
    });

    group('GET /api/packages/search (searchPackages)', () {
      setUp(() async {
        // Create packages for search tests
        await metadata.upsertPackageVersion(
          packageName: 'flutter_bloc',
          version: '1.0.0',
          pubspec: {
            'name': 'flutter_bloc',
            'version': '1.0.0',
            'description': 'BLoC state management for Flutter',
          },
          archiveKey: 'flutter_bloc/1.0.0.tar.gz',
          archiveSha256: 'abc123',
        );

        await metadata.upsertPackageVersion(
          packageName: 'provider',
          version: '2.0.0',
          pubspec: {
            'name': 'provider',
            'version': '2.0.0',
            'description': 'Simple state management',
          },
          archiveKey: 'provider/2.0.0.tar.gz',
          archiveSha256: 'def456',
        );

        await metadata.upsertPackageVersion(
          packageName: 'http',
          version: '1.0.0',
          pubspec: {
            'name': 'http',
            'version': '1.0.0',
            'description': 'HTTP client for Dart',
          },
          archiveKey: 'http/1.0.0.tar.gz',
          archiveSha256: 'ghi789',
        );
      });

      test('returns 400 when query is missing', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/search'),
        );

        final response = await handlers.searchPackages(request);
        expect(response.statusCode, equals(400));

        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['error']['code'], equals('missing_query'));
      });

      test('returns 400 when query is empty', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/search?q='),
        );

        final response = await handlers.searchPackages(request);
        expect(response.statusCode, equals(400));
      });

      test('finds packages by name', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/search?q=flutter'),
        );

        final response = await handlers.searchPackages(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        final packages = body['packages'] as List;
        expect(packages.any((p) => p['name'] == 'flutter_bloc'), isTrue);
      });

      test('finds packages by partial name match', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/search?q=prov'),
        );

        final response = await handlers.searchPackages(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        final packages = body['packages'] as List;
        expect(packages.any((p) => p['name'] == 'provider'), isTrue);
      });

      test('returns empty list when no matches', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/search?q=nonexistent_xyz'),
        );

        final response = await handlers.searchPackages(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        final packages = body['packages'] as List;
        expect(packages.isEmpty, isTrue);
      });

      test('supports pagination in search results', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/search?q=e&page=1&limit=2'),
        );

        final response = await handlers.searchPackages(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['page'], equals(1));
        expect(body['limit'], equals(2));
      });
    });

    group('GET /api/packages/<name> (getPackage)', () {
      test('returns 404 for nonexistent package', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/nonexistent'),
        );

        final response = await handlers.getPackage(request, 'nonexistent');
        expect(response.statusCode, equals(404));
      });

      test('returns package info when package exists', () async {
        await metadata.upsertPackageVersion(
          packageName: 'my_package',
          version: '1.0.0',
          pubspec: {
            'name': 'my_package',
            'version': '1.0.0',
            'description': 'A test package',
          },
          archiveKey: 'my_package/1.0.0.tar.gz',
          archiveSha256: 'abc123',
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/my_package'),
        );

        final response = await handlers.getPackage(request, 'my_package');
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['name'], equals('my_package'));
        expect(body['versions'], isA<List>());
        expect((body['versions'] as List).length, equals(1));
      });

      test('returns all versions of package', () async {
        await metadata.upsertPackageVersion(
          packageName: 'versioned_pkg',
          version: '1.0.0',
          pubspec: {'name': 'versioned_pkg', 'version': '1.0.0'},
          archiveKey: 'versioned_pkg/1.0.0.tar.gz',
          archiveSha256: 'hash1',
        );

        await metadata.upsertPackageVersion(
          packageName: 'versioned_pkg',
          version: '2.0.0',
          pubspec: {'name': 'versioned_pkg', 'version': '2.0.0'},
          archiveKey: 'versioned_pkg/2.0.0.tar.gz',
          archiveSha256: 'hash2',
        );

        await metadata.upsertPackageVersion(
          packageName: 'versioned_pkg',
          version: '3.0.0-beta',
          pubspec: {'name': 'versioned_pkg', 'version': '3.0.0-beta'},
          archiveKey: 'versioned_pkg/3.0.0-beta.tar.gz',
          archiveSha256: 'hash3',
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/versioned_pkg'),
        );

        final response = await handlers.getPackage(request, 'versioned_pkg');
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        final versions = body['versions'] as List;
        expect(versions.length, equals(3));
      });

      test('marks latest version correctly', () async {
        await metadata.upsertPackageVersion(
          packageName: 'latest_test',
          version: '1.0.0',
          pubspec: {'name': 'latest_test', 'version': '1.0.0'},
          archiveKey: 'latest_test/1.0.0.tar.gz',
          archiveSha256: 'hash1',
        );

        await metadata.upsertPackageVersion(
          packageName: 'latest_test',
          version: '2.0.0',
          pubspec: {'name': 'latest_test', 'version': '2.0.0'},
          archiveKey: 'latest_test/2.0.0.tar.gz',
          archiveSha256: 'hash2',
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/latest_test'),
        );

        final response = await handlers.getPackage(request, 'latest_test');
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['latest'], isNotNull);
        expect(body['latest']['version'], equals('2.0.0'));
      });
    });

    group('GET /api/packages/<name>/versions/<version> (getVersion)', () {
      setUp(() async {
        await metadata.upsertPackageVersion(
          packageName: 'version_test',
          version: '1.0.0',
          pubspec: {
            'name': 'version_test',
            'version': '1.0.0',
            'description': 'Version 1.0.0',
          },
          archiveKey: 'version_test/1.0.0.tar.gz',
          archiveSha256: 'hash100',
        );

        await metadata.upsertPackageVersion(
          packageName: 'version_test',
          version: '2.0.0',
          pubspec: {
            'name': 'version_test',
            'version': '2.0.0',
            'description': 'Version 2.0.0',
          },
          archiveKey: 'version_test/2.0.0.tar.gz',
          archiveSha256: 'hash200',
        );
      });

      test('returns 404 for nonexistent package', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/nonexistent/versions/1.0.0'),
        );

        final response =
            await handlers.getVersion(request, 'nonexistent', '1.0.0');
        expect(response.statusCode, equals(404));
      });

      test('returns 404 for nonexistent version', () async {
        final request = Request(
          'GET',
          Uri.parse(
              'http://localhost/api/packages/version_test/versions/99.0.0'),
        );

        final response =
            await handlers.getVersion(request, 'version_test', '99.0.0');
        expect(response.statusCode, equals(404));
      });

      test('returns version info when version exists', () async {
        final request = Request(
          'GET',
          Uri.parse(
              'http://localhost/api/packages/version_test/versions/1.0.0'),
        );

        final response =
            await handlers.getVersion(request, 'version_test', '1.0.0');
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['version'], equals('1.0.0'));
        expect(body['pubspec'], isA<Map>());
        expect(body['archive_url'], contains('1.0.0.tar.gz'));
      });

      test('returns correct archive URL', () async {
        final request = Request(
          'GET',
          Uri.parse(
              'http://localhost/api/packages/version_test/versions/2.0.0'),
        );

        final response =
            await handlers.getVersion(request, 'version_test', '2.0.0');
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['archive_url'], contains('version_test'));
        expect(body['archive_url'], contains('2.0.0'));
      });

      test('returns archive_sha256 hash', () async {
        final request = Request(
          'GET',
          Uri.parse(
              'http://localhost/api/packages/version_test/versions/1.0.0'),
        );

        final response =
            await handlers.getVersion(request, 'version_test', '1.0.0');
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        expect(body['archive_sha256'], isNotEmpty);
      });
    });

    group('Authentication for download endpoints', () {
      test('allows access without auth when requireDownloadAuth is false',
          () async {
        // Default config has requireDownloadAuth: false
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages'),
        );

        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));
      });

      test('requires auth when requireDownloadAuth is true', () async {
        // Create handlers with requireDownloadAuth: true
        final authConfig = Config(
          listenAddr: '0.0.0.0',
          listenPort: 4920,
          baseUrl: 'http://localhost:4920',
          databaseUrl: 'sqlite::memory:',
          storagePath: '${tempDir.path}/storage',
          requirePublishAuth: true,
          requireDownloadAuth: true, // Enable download auth
          signedUrlTtlSeconds: 3600,
          upstreamUrl: 'https://pub.dev',
          enableUpstreamProxy: false,
          rateLimitRequests: 100,
          rateLimitWindowSeconds: 60,
        );

        final authHandlers = ApiHandlers(
          config: authConfig,
          metadata: metadata,
          blobs: blobs,
          cacheBlobs: cacheBlobs,
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages'),
        );

        final response = await authHandlers.listPackages(request);
        // Should return 401 or 403 when no auth provided
        expect(response.statusCode, anyOf(equals(401), equals(403)));
      });

      test('allows access with valid token when requireDownloadAuth is true',
          () async {
        // Create a user and token
        final userId = await metadata.createUser(
          email: 'test@example.com',
          passwordHash: 'hash',
        );
        final tokenId = await metadata.createToken(
          userId: userId,
          label: 'read_token',
          scopes: ['admin'],
        );

        // Create handlers with requireDownloadAuth: true
        final authConfig = Config(
          listenAddr: '0.0.0.0',
          listenPort: 4920,
          baseUrl: 'http://localhost:4920',
          databaseUrl: 'sqlite::memory:',
          storagePath: '${tempDir.path}/storage',
          requirePublishAuth: true,
          requireDownloadAuth: true,
          signedUrlTtlSeconds: 3600,
          upstreamUrl: 'https://pub.dev',
          enableUpstreamProxy: false,
          rateLimitRequests: 100,
          rateLimitWindowSeconds: 60,
        );

        final authHandlers = ApiHandlers(
          config: authConfig,
          metadata: metadata,
          blobs: blobs,
          cacheBlobs: cacheBlobs,
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages'),
          headers: {'Authorization': 'Bearer $tokenId'},
        );

        final response = await authHandlers.listPackages(request);
        expect(response.statusCode, equals(200));
      });
    });

    group('Response headers', () {
      test('listPackages returns JSON content type', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages'),
        );

        final response = await handlers.listPackages(request);
        expect(response.headers['content-type'], equals('application/json'));
      });

      test('searchPackages returns JSON content type', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/search?q=test'),
        );

        final response = await handlers.searchPackages(request);
        expect(response.headers['content-type'], equals('application/json'));
      });

      test('getPackage returns JSON content type', () async {
        await metadata.upsertPackageVersion(
          packageName: 'header_test',
          version: '1.0.0',
          pubspec: {'name': 'header_test', 'version': '1.0.0'},
          archiveKey: 'header_test/1.0.0.tar.gz',
          archiveSha256: 'hash',
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/api/packages/header_test'),
        );

        final response = await handlers.getPackage(request, 'header_test');
        expect(response.headers['content-type'], equals('application/json'));
      });
    });
  });
}
