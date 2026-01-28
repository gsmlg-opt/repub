import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:repub_model/repub_model.dart';
import 'package:repub_server/src/handlers.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('Authorization Integration Tests', () {
    late MetadataStore metadata;
    late Config config;
    late Directory tempDir;

    setUp(() async {
      // Create temporary directory for test database
      tempDir = await Directory.systemTemp.createTemp('repub_auth_test_');

      config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite:${tempDir.path}/test.db',
        storagePath: tempDir.path,
        requirePublishAuth: true,
        requireDownloadAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: false,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      metadata = await MetadataStore.create(config);
      await metadata.runMigrations();
    });

    tearDown(() async {
      await metadata.close();
      await tempDir.delete(recursive: true);
    });

    group('Token Creation with Scopes', () {
      test('tokens can be created with admin scope', () async {
        final userId = await metadata.createUser(
          email: 'admin@example.com',
          passwordHash: 'hash',
        );
        final token = await metadata.createToken(
          userId: userId,
          label: 'Admin Token',
          scopes: ['admin'],
        );

        expect(token, isNotNull);

        // Retrieve and verify
        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.length, equals(1));
        expect(tokens.first.scopes, contains('admin'));
        expect(tokens.first.isAdmin, isTrue);
      });

      test('tokens can be created with publish:all scope', () async {
        final userId = await metadata.createUser(
          email: 'publisher@example.com',
          passwordHash: 'hash',
        );
        final token = await metadata.createToken(
          userId: userId,
          label: 'Publish All Token',
          scopes: ['publish:all'],
        );

        expect(token, isNotNull);

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.first.scopes, contains('publish:all'));
        expect(tokens.first.canPublishAll, isTrue);
      });

      test('tokens can be created with package-specific scope', () async {
        final userId = await metadata.createUser(
          email: 'dev@example.com',
          passwordHash: 'hash',
        );
        final token = await metadata.createToken(
          userId: userId,
          label: 'Package Specific Token',
          scopes: ['publish:pkg:my_package'],
        );

        expect(token, isNotNull);

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.first.scopes, contains('publish:pkg:my_package'));
        expect(tokens.first.canPublish('my_package'), isTrue);
        expect(tokens.first.canPublish('other_package'), isFalse);
      });

      test('tokens can be created with read:all scope', () async {
        final userId = await metadata.createUser(
          email: 'reader@example.com',
          passwordHash: 'hash',
        );
        final token = await metadata.createToken(
          userId: userId,
          label: 'Reader Token',
          scopes: ['read:all'],
        );

        expect(token, isNotNull);

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.first.scopes, contains('read:all'));
        expect(tokens.first.canRead, isTrue);
      });

      test('tokens can be created with multiple scopes', () async {
        final userId = await metadata.createUser(
          email: 'multi@example.com',
          passwordHash: 'hash',
        );
        final token = await metadata.createToken(
          userId: userId,
          label: 'Multi Scope Token',
          scopes: ['publish:all', 'read:all'],
        );

        expect(token, isNotNull);

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.first.scopes.length, equals(2));
        expect(tokens.first.scopes, contains('publish:all'));
        expect(tokens.first.scopes, contains('read:all'));
        expect(tokens.first.canPublishAll, isTrue);
        expect(tokens.first.canRead, isTrue);
      });

      test('tokens can be created with empty scopes', () async {
        final userId = await metadata.createUser(
          email: 'noscope@example.com',
          passwordHash: 'hash',
        );
        final token = await metadata.createToken(
          userId: userId,
          label: 'No Scopes Token',
          scopes: [],
        );

        expect(token, isNotNull);

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.first.scopes, isEmpty);
        expect(tokens.first.isAdmin, isFalse);
        expect(tokens.first.canPublishAll, isFalse);
        expect(tokens.first.canRead, isFalse);
      });
    });

    group('Token Scope Persistence', () {
      test('scopes persist across database queries', () async {
        final userId = await metadata.createUser(
          email: 'persist@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'Persistence Test',
          scopes: ['admin', 'publish:all', 'read:all'],
        );

        // List tokens to verify scopes were persisted
        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.length, equals(1));

        final persistedToken = tokens.first;
        expect(persistedToken.label, equals('Persistence Test'));
        expect(persistedToken.scopes.length, equals(3));
        expect(persistedToken.scopes, contains('admin'));
        expect(persistedToken.scopes, contains('publish:all'));
        expect(persistedToken.scopes, contains('read:all'));
      });

      test('multiple tokens with different scopes for same user', () async {
        final userId = await metadata.createUser(
          email: 'multitokens@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'Admin Token',
          scopes: ['admin'],
        );

        await metadata.createToken(
          userId: userId,
          label: 'Publish Token',
          scopes: ['publish:pkg:my_package'],
        );

        await metadata.createToken(
          userId: userId,
          label: 'Read Token',
          scopes: ['read:all'],
        );

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.length, equals(3));

        final adminToken = tokens.firstWhere((t) => t.label == 'Admin Token');
        expect(adminToken.scopes, contains('admin'));

        final publishToken =
            tokens.firstWhere((t) => t.label == 'Publish Token');
        expect(publishToken.scopes, contains('publish:pkg:my_package'));

        final readToken = tokens.firstWhere((t) => t.label == 'Read Token');
        expect(readToken.scopes, contains('read:all'));
      });
    });

    group('Token Deletion', () {
      test('token deletion removes token and scopes', () async {
        final userId = await metadata.createUser(
          email: 'delete@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'To Be Deleted',
          scopes: ['publish:pkg:temp'],
        );

        final tokensBefore = await metadata.listTokens(userId: userId);
        expect(tokensBefore.length, equals(1));

        await metadata.deleteToken('To Be Deleted');

        final tokensAfter = await metadata.listTokens(userId: userId);
        expect(tokensAfter.length, equals(0));
      });
    });

    group('AuthToken Helper Methods', () {
      test('isAdmin returns true only for admin scope', () async {
        final userId = await metadata.createUser(
          email: 'test@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'Admin',
          scopes: ['admin'],
        );

        await metadata.createToken(
          userId: userId,
          label: 'Not Admin',
          scopes: ['publish:all'],
        );

        final tokens = await metadata.listTokens(userId: userId);
        final adminToken = tokens.firstWhere((t) => t.label == 'Admin');
        final notAdminToken = tokens.firstWhere((t) => t.label == 'Not Admin');

        expect(adminToken.isAdmin, isTrue);
        expect(notAdminToken.isAdmin, isFalse);
      });

      test('canPublishAll works correctly', () async {
        final userId = await metadata.createUser(
          email: 'test@example.com',
          passwordHash: 'hash',
        );

        await metadata
            .createToken(userId: userId, label: 'Admin', scopes: ['admin']);
        await metadata.createToken(
            userId: userId, label: 'PublishAll', scopes: ['publish:all']);
        await metadata.createToken(
            userId: userId, label: 'PublishPkg', scopes: ['publish:pkg:foo']);
        await metadata.createToken(
            userId: userId, label: 'ReadAll', scopes: ['read:all']);

        final tokens = await metadata.listTokens(userId: userId);

        expect(
            tokens.firstWhere((t) => t.label == 'Admin').canPublishAll, isTrue);
        expect(tokens.firstWhere((t) => t.label == 'PublishAll').canPublishAll,
            isTrue);
        expect(tokens.firstWhere((t) => t.label == 'PublishPkg').canPublishAll,
            isFalse);
        expect(tokens.firstWhere((t) => t.label == 'ReadAll').canPublishAll,
            isFalse);
      });

      test('canPublish checks package-specific scopes', () async {
        final userId = await metadata.createUser(
          email: 'test@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
            userId: userId, label: 'Foo', scopes: ['publish:pkg:foo']);
        await metadata.createToken(
            userId: userId, label: 'Bar', scopes: ['publish:pkg:bar']);

        final tokens = await metadata.listTokens(userId: userId);
        final fooToken = tokens.firstWhere((t) => t.label == 'Foo');
        final barToken = tokens.firstWhere((t) => t.label == 'Bar');

        expect(fooToken.canPublish('foo'), isTrue);
        expect(fooToken.canPublish('bar'), isFalse);
        expect(barToken.canPublish('bar'), isTrue);
        expect(barToken.canPublish('foo'), isFalse);
      });

      test('canRead returns true for admin or read:all', () async {
        final userId = await metadata.createUser(
          email: 'test@example.com',
          passwordHash: 'hash',
        );

        await metadata
            .createToken(userId: userId, label: 'Admin', scopes: ['admin']);
        await metadata.createToken(
            userId: userId, label: 'ReadAll', scopes: ['read:all']);
        await metadata.createToken(
            userId: userId, label: 'PublishAll', scopes: ['publish:all']);

        final tokens = await metadata.listTokens(userId: userId);

        expect(tokens.firstWhere((t) => t.label == 'Admin').canRead, isTrue);
        expect(tokens.firstWhere((t) => t.label == 'ReadAll').canRead, isTrue);
        expect(
            tokens.firstWhere((t) => t.label == 'PublishAll').canRead, isFalse);
      });
    });

    group('Security Scenarios', () {
      test('admin scope grants all permissions', () async {
        final userId = await metadata.createUser(
          email: 'superadmin@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'Super Admin',
          scopes: ['admin'],
        );

        final tokens = await metadata.listTokens(userId: userId);
        final adminToken = tokens.first;

        expect(adminToken.isAdmin, isTrue);
        expect(adminToken.canPublishAll, isTrue);
        expect(adminToken.canPublish('any_package'), isTrue);
        expect(adminToken.canRead, isTrue);
      });

      test('publish:all grants publish but not admin', () async {
        final userId = await metadata.createUser(
          email: 'publisher@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'Universal Publisher',
          scopes: ['publish:all'],
        );

        final tokens = await metadata.listTokens(userId: userId);
        final publishToken = tokens.first;

        expect(publishToken.isAdmin, isFalse);
        expect(publishToken.canPublishAll, isTrue);
        expect(publishToken.canPublish('any_package'), isTrue);
        expect(publishToken.canRead, isFalse);
      });

      test('package-specific scope is restrictive', () async {
        final userId = await metadata.createUser(
          email: 'restricted@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'Restricted Publisher',
          scopes: ['publish:pkg:my_package'],
        );

        final tokens = await metadata.listTokens(userId: userId);
        final restrictedToken = tokens.first;

        expect(restrictedToken.isAdmin, isFalse);
        expect(restrictedToken.canPublishAll, isFalse);
        expect(restrictedToken.canPublish('my_package'), isTrue);
        expect(restrictedToken.canPublish('other_package'), isFalse);
        expect(restrictedToken.canRead, isFalse);
      });
    });

    group('Token Expiration', () {
      test('token can be created with expiration date', () async {
        final userId = await metadata.createUser(
          email: 'expires@example.com',
          passwordHash: 'hash',
        );

        final expiresAt = DateTime.now().add(const Duration(days: 30));
        await metadata.createToken(
          userId: userId,
          label: 'Expiring Token',
          scopes: ['publish:all'],
          expiresAt: expiresAt,
        );

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.length, equals(1));
        expect(tokens.first.expiresAt, isNotNull);
        expect(tokens.first.isExpired, isFalse);
      });

      test('expired token reports as expired', () async {
        final userId = await metadata.createUser(
          email: 'expired@example.com',
          passwordHash: 'hash',
        );

        // Create token that expired in the past
        final expiresAt = DateTime.now().subtract(const Duration(hours: 1));
        await metadata.createToken(
          userId: userId,
          label: 'Expired Token',
          scopes: ['publish:all'],
          expiresAt: expiresAt,
        );

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.length, equals(1));
        expect(tokens.first.expiresAt, isNotNull);
        expect(tokens.first.isExpired, isTrue);
      });

      test('token without expiration never expires', () async {
        final userId = await metadata.createUser(
          email: 'permanent@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'Permanent Token',
          scopes: ['publish:all'],
        );

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.length, equals(1));
        expect(tokens.first.expiresAt, isNull);
        expect(tokens.first.isExpired, isFalse);
      });

      test('token_max_ttl_days config can be set and retrieved', () async {
        // Set maximum TTL to 90 days
        await metadata.setConfig('token_max_ttl_days', '90');

        final config = await metadata.getConfig('token_max_ttl_days');
        expect(config, isNotNull);
        expect(config!.value, equals('90'));
        expect(config.intValue, equals(90));
      });

      test('token_max_ttl_days defaults to 0 (unlimited)', () async {
        final config = await metadata.getConfig('token_max_ttl_days');
        expect(config, isNotNull);
        expect(config!.intValue, equals(0));
      });
    });

    group('Download Scope Enforcement', () {
      late Config authConfig;
      late BlobStore blobs;
      late ApiHandlers handlers;
      late String userId;
      late String tokenWithReadScope;
      late String tokenWithoutReadScope;

      setUp(() async {
        // Create config that requires download auth
        authConfig = Config(
          listenAddr: '0.0.0.0',
          listenPort: 4920,
          baseUrl: 'http://localhost:4920',
          databaseUrl: config.databaseUrl,
          storagePath: tempDir.path,
          requirePublishAuth: true,
          requireDownloadAuth: true, // Enable download auth
          signedUrlTtlSeconds: 3600,
          upstreamUrl: 'https://pub.dev',
          enableUpstreamProxy: false,
          rateLimitRequests: 100,
          rateLimitWindowSeconds: 60,
        );

        // Create blob storage
        blobs = BlobStore.fromConfig(authConfig);
        await blobs.ensureReady();

        // Create handlers
        handlers = ApiHandlers(
          config: authConfig,
          metadata: metadata,
          blobs: blobs,
          cacheBlobs: blobs,
        );

        // Create user
        userId = await metadata.createUser(
          email: 'downloader@example.com',
          passwordHash: 'hash',
        );

        // Create token WITH read:all scope
        tokenWithReadScope = await metadata.createToken(
          userId: userId,
          label: 'Can Read',
          scopes: ['read:all'],
        );

        // Create token WITHOUT read:all scope (only publish)
        tokenWithoutReadScope = await metadata.createToken(
          userId: userId,
          label: 'Cannot Read',
          scopes: ['publish:all'],
        );

        // Create test package
        await metadata.upsertPackageVersion(
          packageName: 'test_package',
          version: '1.0.0',
          pubspec: {'name': 'test_package', 'version': '1.0.0'},
          archiveKey: 'test_package/1.0.0/abc123',
          archiveSha256: 'abc123',
        );
      });

      tearDown(() async {
        // BlobStore doesn't need explicit cleanup
      });

      test('listPackages requires read:all scope when download auth enabled',
          () async {
        // Request without read scope should fail
        final requestNoScope = Request(
          'GET',
          Uri.parse('http://localhost:4920/api/packages'),
          headers: {
            'authorization':
                'Bearer $tokenWithoutReadScope',
          },
        );
        final responseNoScope = await handlers.listPackages(requestNoScope);
        expect(responseNoScope.statusCode, equals(403));

        // Request with read scope should succeed
        final requestWithScope = Request(
          'GET',
          Uri.parse('http://localhost:4920/api/packages'),
          headers: {
            'authorization':
                'Bearer $tokenWithReadScope',
          },
        );
        final responseWithScope =
            await handlers.listPackages(requestWithScope);
        expect(responseWithScope.statusCode, equals(200));
      });

      test('searchPackages requires read:all scope when download auth enabled',
          () async {
        final requestNoScope = Request(
          'GET',
          Uri.parse('http://localhost:4920/api/packages/search?q=test'),
          headers: {
            'authorization':
                'Bearer $tokenWithoutReadScope',
          },
        );
        final responseNoScope = await handlers.searchPackages(requestNoScope);
        expect(responseNoScope.statusCode, equals(403));

        final requestWithScope = Request(
          'GET',
          Uri.parse('http://localhost:4920/api/packages/search?q=test'),
          headers: {
            'authorization':
                'Bearer $tokenWithReadScope',
          },
        );
        final responseWithScope =
            await handlers.searchPackages(requestWithScope);
        expect(responseWithScope.statusCode, equals(200));
      });

      test('getPackage requires read:all scope when download auth enabled',
          () async {
        final requestNoScope = Request(
          'GET',
          Uri.parse('http://localhost:4920/api/packages/test_package'),
          headers: {
            'authorization':
                'Bearer $tokenWithoutReadScope',
          },
        );
        final responseNoScope =
            await handlers.getPackage(requestNoScope, 'test_package');
        expect(responseNoScope.statusCode, equals(403));

        final requestWithScope = Request(
          'GET',
          Uri.parse('http://localhost:4920/api/packages/test_package'),
          headers: {
            'authorization':
                'Bearer $tokenWithReadScope',
          },
        );
        final responseWithScope =
            await handlers.getPackage(requestWithScope, 'test_package');
        expect(responseWithScope.statusCode, equals(200));
      });

      test('getVersion requires read:all scope when download auth enabled',
          () async {
        final requestNoScope = Request(
          'GET',
          Uri.parse(
              'http://localhost:4920/api/packages/test_package/versions/1.0.0'),
          headers: {
            'authorization':
                'Bearer $tokenWithoutReadScope',
          },
        );
        final responseNoScope = await handlers.getVersion(
            requestNoScope, 'test_package', '1.0.0');
        expect(responseNoScope.statusCode, equals(403));

        final requestWithScope = Request(
          'GET',
          Uri.parse(
              'http://localhost:4920/api/packages/test_package/versions/1.0.0'),
          headers: {
            'authorization':
                'Bearer $tokenWithReadScope',
          },
        );
        final responseWithScope = await handlers.getVersion(
            requestWithScope, 'test_package', '1.0.0');
        expect(responseWithScope.statusCode, equals(200));
      });

      test('downloadPackage requires read:all scope when download auth enabled',
          () async {
        final requestNoScope = Request(
          'GET',
          Uri.parse(
              'http://localhost:4920/packages/test_package/versions/1.0.0.tar.gz'),
          headers: {
            'authorization':
                'Bearer $tokenWithoutReadScope',
          },
        );
        final responseNoScope = await handlers.downloadPackage(
            requestNoScope, 'test_package', '1.0.0');
        expect(responseNoScope.statusCode, equals(403));

        // Note: We can't fully test successful download without actual blob data,
        // but we can verify the scope check passes (would fail later on missing blob)
        final requestWithScope = Request(
          'GET',
          Uri.parse(
              'http://localhost:4920/packages/test_package/versions/1.0.0.tar.gz'),
          headers: {
            'authorization':
                'Bearer $tokenWithReadScope',
          },
        );
        final responseWithScope = await handlers.downloadPackage(
            requestWithScope, 'test_package', '1.0.0');
        // Should pass scope check (403 = scope fail, 404/500 = scope passed but blob missing)
        expect(responseWithScope.statusCode, isNot(equals(403)));
      });

      test('admin scope grants read access', () async {
        // Create admin token
        final adminToken = await metadata.createToken(
          userId: userId,
          label: 'Admin',
          scopes: ['admin'],
        );

        final request = Request(
          'GET',
          Uri.parse('http://localhost:4920/api/packages'),
          headers: {
            'authorization': 'Bearer $adminToken',
          },
        );
        final response = await handlers.listPackages(request);
        expect(response.statusCode, equals(200));
      });
    });
  });
}
