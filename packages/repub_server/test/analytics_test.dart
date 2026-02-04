import 'dart:convert';
import 'dart:io';

import 'package:repub_model/repub_model.dart';
import 'package:repub_server/src/handlers.dart';
import 'package:repub_server/src/password_crypto.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('Analytics API Tests', () {
    late SqliteMetadataStore metadata;
    late BlobStore blobs;
    late BlobStore cacheBlobs;
    late Config config;
    late ApiHandlers handlers;
    late String adminSessionId;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('repub_analytics_test_');

      metadata = SqliteMetadataStore.inMemory();
      await metadata.runMigrations();

      blobs = FileBlobStore(
          basePath: '${tempDir.path}/storage',
          baseUrl: 'http://localhost:4920');
      cacheBlobs = FileBlobStore(
          basePath: '${tempDir.path}/cache',
          baseUrl: 'http://localhost:4920',
          isCache: true);

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
        passwordCrypto: PasswordCrypto(),
      );

      // Create admin user and session for all tests
      final adminId = await metadata.createAdminUser(
        username: 'admin',
        passwordHash: 'hash',
      );
      final session = await metadata.createAdminSession(
        adminUserId: adminId,
      );
      adminSessionId = session.sessionId;
    });

    tearDown(() async {
      await metadata.close();
      await tempDir.delete(recursive: true);
    });

    group('Packages Created Analytics', () {
      test('returns empty map when no packages exist', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/analytics/packages-created'),
          headers: {
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminGetPackagesCreatedPerDay(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        // Map should be empty when no packages
        expect(body.isEmpty, isTrue);
      });

      test('returns package creation counts when packages exist', () async {
        // Create a package
        await metadata.upsertPackageVersion(
          packageName: 'test_package',
          version: '1.0.0',
          pubspec: {'name': 'test_package', 'version': '1.0.0'},
          archiveKey: 'test_package/1.0.0.tar.gz',
          archiveSha256: 'abc123',
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/analytics/packages-created'),
          headers: {
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminGetPackagesCreatedPerDay(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        // Map should have at least one entry (today)
        expect(body.isNotEmpty, isTrue);
        // Sum should be at least 1
        final total =
            body.values.fold<int>(0, (sum, count) => sum + (count as int));
        expect(total, greaterThanOrEqualTo(1));
      });

      test('requires admin authentication', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/analytics/packages-created'),
        );

        final response = await handlers.adminGetPackagesCreatedPerDay(request);
        expect(response.statusCode, equals(401));
      });
    });

    group('Downloads Analytics', () {
      test('returns empty map when no downloads recorded', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/analytics/downloads'),
          headers: {
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminGetDownloadsPerHour(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        // Map should be empty when no downloads
        expect(body.isEmpty, isTrue);
      });

      test('returns download counts when downloads recorded', () async {
        // Create a package first
        await metadata.upsertPackageVersion(
          packageName: 'download_test',
          version: '1.0.0',
          pubspec: {'name': 'download_test', 'version': '1.0.0'},
          archiveKey: 'download_test/1.0.0.tar.gz',
          archiveSha256: 'def456',
        );

        // Record some downloads
        await metadata.logDownload(
          packageName: 'download_test',
          version: '1.0.0',
          ipAddress: '192.168.1.1',
        );
        await metadata.logDownload(
          packageName: 'download_test',
          version: '1.0.0',
          ipAddress: '192.168.1.2',
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/analytics/downloads'),
          headers: {
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminGetDownloadsPerHour(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString()) as Map;
        // Map should have at least one entry
        expect(body.isNotEmpty, isTrue);
        // Sum should be 2
        final total =
            body.values.fold<int>(0, (sum, count) => sum + (count as int));
        expect(total, equals(2));
      });

      test('requires admin authentication', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/analytics/downloads'),
        );

        final response = await handlers.adminGetDownloadsPerHour(request);
        expect(response.statusCode, equals(401));
      });
    });

    group('Package Stats', () {
      test('returns 404 for non-existent package', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/packages/nonexistent/stats'),
          headers: {
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response =
            await handlers.adminGetPackageStats(request, 'nonexistent');
        expect(response.statusCode, equals(404));

        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('not_found'));
      });

      test('returns stats for existing package', () async {
        // Create a package
        await metadata.upsertPackageVersion(
          packageName: 'stats_package',
          version: '1.0.0',
          pubspec: {'name': 'stats_package', 'version': '1.0.0'},
          archiveKey: 'stats_package/1.0.0.tar.gz',
          archiveSha256: 'ghi789',
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/packages/stats_package/stats'),
          headers: {
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response =
            await handlers.adminGetPackageStats(request, 'stats_package');
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString());
        expect(body['package']['name'], equals('stats_package'));
        expect(body['version_count'], equals(1));
        expect(body['latest_version'], equals('1.0.0'));
        expect(body['stats'], isNotNull);
      });

      test('returns correct download counts for package', () async {
        // Create a package
        await metadata.upsertPackageVersion(
          packageName: 'counted_package',
          version: '1.0.0',
          pubspec: {'name': 'counted_package', 'version': '1.0.0'},
          archiveKey: 'counted_package/1.0.0.tar.gz',
          archiveSha256: 'jkl012',
        );

        // Record downloads
        for (var i = 0; i < 5; i++) {
          await metadata.logDownload(
            packageName: 'counted_package',
            version: '1.0.0',
            ipAddress: '192.168.1.$i',
          );
        }

        final request = Request(
          'GET',
          Uri.parse(
              'http://localhost/admin/api/packages/counted_package/stats'),
          headers: {
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response =
            await handlers.adminGetPackageStats(request, 'counted_package');
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString());
        expect(body['stats']['total_downloads'], equals(5));
      });

      test('requires admin authentication', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/packages/anypackage/stats'),
        );

        final response =
            await handlers.adminGetPackageStats(request, 'anypackage');
        expect(response.statusCode, equals(401));
      });
    });

    group('Admin Stats Dashboard', () {
      test('returns overview statistics', () async {
        // Create some test data
        await metadata.upsertPackageVersion(
          packageName: 'pkg1',
          version: '1.0.0',
          pubspec: {'name': 'pkg1', 'version': '1.0.0'},
          archiveKey: 'pkg1/1.0.0.tar.gz',
          archiveSha256: 'aaa111',
        );

        await metadata.createUser(
          email: 'user@example.com',
          passwordHash: 'hash',
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/stats'),
          headers: {
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminGetStats(request);
        expect(response.statusCode, equals(200));

        final body = jsonDecode(await response.readAsString());
        // Check the correct field names (camelCase from AdminStats.toJson)
        expect(body['localPackages'], greaterThanOrEqualTo(1));
        expect(body['totalUsers'], greaterThanOrEqualTo(1));
      });

      test('requires admin authentication', () async {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/admin/api/stats'),
        );

        final response = await handlers.adminGetStats(request);
        expect(response.statusCode, equals(401));
      });
    });
  });
}
