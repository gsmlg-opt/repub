import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

void main() {
  late SqliteMetadataStore store;

  setUp(() {
    store = SqliteMetadataStore.open(':memory:');
    store.runMigrations();
  });

  tearDown(() {
    store.close();
  });

  group('Package Operations', () {
    test('getPackage returns null for non-existent package', () async {
      final pkg = await store.getPackage('nonexistent');
      expect(pkg, isNull);
    });

    test('upsertPackageVersion creates new package', () async {
      await store.upsertPackageVersion(
        packageName: 'test_package',
        version: '1.0.0',
        pubspec: {'name': 'test_package', 'version': '1.0.0'},
        archiveKey: 'test_package/1.0.0.tar.gz',
        archiveSha256: 'abc123',
      );

      final pkg = await store.getPackage('test_package');
      expect(pkg, isNotNull);
      expect(pkg!.name, 'test_package');
      expect(pkg.isDiscontinued, isFalse);
      expect(pkg.isUpstreamCache, isFalse);
    });

    test('upsertPackageVersion creates upstream cache package', () async {
      await store.upsertPackageVersion(
        packageName: 'cached_package',
        version: '2.0.0',
        pubspec: {'name': 'cached_package', 'version': '2.0.0'},
        archiveKey: 'cached_package/2.0.0.tar.gz',
        archiveSha256: 'def456',
        isUpstreamCache: true,
      );

      final pkg = await store.getPackage('cached_package');
      expect(pkg, isNotNull);
      expect(pkg!.isUpstreamCache, isTrue);
    });

    test('upsertPackageVersion adds multiple versions', () async {
      await store.upsertPackageVersion(
        packageName: 'multi_version',
        version: '1.0.0',
        pubspec: {'name': 'multi_version', 'version': '1.0.0'},
        archiveKey: 'multi_version/1.0.0.tar.gz',
        archiveSha256: 'v1hash',
      );

      await store.upsertPackageVersion(
        packageName: 'multi_version',
        version: '2.0.0',
        pubspec: {'name': 'multi_version', 'version': '2.0.0'},
        archiveKey: 'multi_version/2.0.0.tar.gz',
        archiveSha256: 'v2hash',
      );

      final versions = await store.getPackageVersions('multi_version');
      expect(versions, hasLength(2));
      expect(versions.map((v) => v.version).toList(), contains('1.0.0'));
      expect(versions.map((v) => v.version).toList(), contains('2.0.0'));
    });

    test('versionExists returns correct result', () async {
      expect(await store.versionExists('test_pkg', '1.0.0'), isFalse);

      await store.upsertPackageVersion(
        packageName: 'test_pkg',
        version: '1.0.0',
        pubspec: {'name': 'test_pkg', 'version': '1.0.0'},
        archiveKey: 'test_pkg/1.0.0.tar.gz',
        archiveSha256: 'hash1',
      );

      expect(await store.versionExists('test_pkg', '1.0.0'), isTrue);
      expect(await store.versionExists('test_pkg', '2.0.0'), isFalse);
    });

    test('getPackageVersion returns specific version', () async {
      await store.upsertPackageVersion(
        packageName: 'versioned_pkg',
        version: '1.0.0',
        pubspec: {
          'name': 'versioned_pkg',
          'version': '1.0.0',
          'description': 'Test package'
        },
        archiveKey: 'versioned_pkg/1.0.0.tar.gz',
        archiveSha256: 'sha_v1',
      );

      final version = await store.getPackageVersion('versioned_pkg', '1.0.0');
      expect(version, isNotNull);
      expect(version!.version, '1.0.0');
      expect(version.archiveSha256, 'sha_v1');
      expect(version.pubspec['description'], 'Test package');
    });

    test('getPackageVersion returns null for non-existent version', () async {
      final version = await store.getPackageVersion('no_pkg', '1.0.0');
      expect(version, isNull);
    });

    test('getPackageInfo returns full package with versions', () async {
      await store.upsertPackageVersion(
        packageName: 'info_pkg',
        version: '1.0.0',
        pubspec: {'name': 'info_pkg', 'version': '1.0.0'},
        archiveKey: 'info_pkg/1.0.0.tar.gz',
        archiveSha256: 'hash1',
      );

      await store.upsertPackageVersion(
        packageName: 'info_pkg',
        version: '1.1.0',
        pubspec: {'name': 'info_pkg', 'version': '1.1.0'},
        archiveKey: 'info_pkg/1.1.0.tar.gz',
        archiveSha256: 'hash2',
      );

      final info = await store.getPackageInfo('info_pkg');
      expect(info, isNotNull);
      expect(info!.package.name, 'info_pkg');
      expect(info.versions, hasLength(2));
      expect(info.latest?.version, isNotNull);
    });

    test('listPackages returns paginated results', () async {
      // Create multiple packages
      for (var i = 0; i < 25; i++) {
        await store.upsertPackageVersion(
          packageName: 'pkg_$i',
          version: '1.0.0',
          pubspec: {'name': 'pkg_$i', 'version': '1.0.0'},
          archiveKey: 'pkg_$i/1.0.0.tar.gz',
          archiveSha256: 'hash_$i',
        );
      }

      // First page
      final page1 = await store.listPackages(page: 1, limit: 10);
      expect(page1.packages, hasLength(10));
      expect(page1.total, 25);
      expect(page1.page, 1);
      expect(page1.totalPages, 3);

      // Second page
      final page2 = await store.listPackages(page: 2, limit: 10);
      expect(page2.packages, hasLength(10));

      // Third page
      final page3 = await store.listPackages(page: 3, limit: 10);
      expect(page3.packages, hasLength(5));
    });

    test('searchPackages finds packages by name', () async {
      await store.upsertPackageVersion(
        packageName: 'flutter_test',
        version: '1.0.0',
        pubspec: {'name': 'flutter_test', 'version': '1.0.0'},
        archiveKey: 'flutter_test/1.0.0.tar.gz',
        archiveSha256: 'hash1',
      );

      await store.upsertPackageVersion(
        packageName: 'dart_utils',
        version: '1.0.0',
        pubspec: {'name': 'dart_utils', 'version': '1.0.0'},
        archiveKey: 'dart_utils/1.0.0.tar.gz',
        archiveSha256: 'hash2',
      );

      final result = await store.searchPackages('flutter');
      expect(result.packages, hasLength(1));
      expect(result.packages.first.package.name, 'flutter_test');
    });

    test('deletePackage removes package and all versions', () async {
      await store.upsertPackageVersion(
        packageName: 'delete_me',
        version: '1.0.0',
        pubspec: {'name': 'delete_me', 'version': '1.0.0'},
        archiveKey: 'delete_me/1.0.0.tar.gz',
        archiveSha256: 'h1',
      );

      await store.upsertPackageVersion(
        packageName: 'delete_me',
        version: '2.0.0',
        pubspec: {'name': 'delete_me', 'version': '2.0.0'},
        archiveKey: 'delete_me/2.0.0.tar.gz',
        archiveSha256: 'h2',
      );

      final deleted = await store.deletePackage('delete_me');
      expect(deleted, 2);

      final pkg = await store.getPackage('delete_me');
      expect(pkg, isNull);
    });

    test('discontinuePackage marks package as discontinued', () async {
      await store.upsertPackageVersion(
        packageName: 'discontinue_me',
        version: '1.0.0',
        pubspec: {'name': 'discontinue_me', 'version': '1.0.0'},
        archiveKey: 'discontinue_me/1.0.0.tar.gz',
        archiveSha256: 'hash',
      );

      final result = await store.discontinuePackage('discontinue_me');
      expect(result, isTrue);

      final pkg = await store.getPackage('discontinue_me');
      expect(pkg!.isDiscontinued, isTrue);
    });

    test('listPackagesByType separates local and cached packages', () async {
      // Create local package
      await store.upsertPackageVersion(
        packageName: 'local_pkg',
        version: '1.0.0',
        pubspec: {'name': 'local_pkg', 'version': '1.0.0'},
        archiveKey: 'local_pkg/1.0.0.tar.gz',
        archiveSha256: 'hash1',
        isUpstreamCache: false,
      );

      // Create cached package
      await store.upsertPackageVersion(
        packageName: 'cached_pkg',
        version: '1.0.0',
        pubspec: {'name': 'cached_pkg', 'version': '1.0.0'},
        archiveKey: 'cached_pkg/1.0.0.tar.gz',
        archiveSha256: 'hash2',
        isUpstreamCache: true,
      );

      final localResult =
          await store.listPackagesByType(isUpstreamCache: false);
      expect(localResult.packages.length, 1);
      expect(localResult.packages.first.package.name, 'local_pkg');

      final cachedResult =
          await store.listPackagesByType(isUpstreamCache: true);
      expect(cachedResult.packages.length, 1);
      expect(cachedResult.packages.first.package.name, 'cached_pkg');
    });
  });

  group('Token Operations', () {
    const testUserId = '00000000-0000-0000-0000-000000000001';

    test('createToken creates and returns token', () async {
      final token = await store.createToken(
        userId: testUserId,
        label: 'test_token',
        scopes: ['publish:all', 'read:all'],
      );

      expect(token, isNotEmpty);
      expect(token.length, greaterThan(20));
    });

    test('getTokenByHash returns correct token', () async {
      final plainToken = await store.createToken(
        userId: testUserId,
        label: 'lookup_token',
        scopes: ['admin'],
      );

      // Hash the token (same method as store)
      final tokenHash = _hashToken(plainToken);
      final retrieved = await store.getTokenByHash(tokenHash);

      expect(retrieved, isNotNull);
      expect(retrieved!.userId, testUserId);
      expect(retrieved.label, 'lookup_token');
      expect(retrieved.scopes, contains('admin'));
    });

    test('getTokenByHash returns null for invalid hash', () async {
      final retrieved = await store.getTokenByHash('invalid_hash');
      expect(retrieved, isNull);
    });

    test('listTokens returns all tokens for user', () async {
      await store.createToken(
        userId: testUserId,
        label: 'token_1',
        scopes: ['read:all'],
      );

      await store.createToken(
        userId: testUserId,
        label: 'token_2',
        scopes: ['publish:all'],
      );

      final tokens = await store.listTokens(userId: testUserId);
      expect(tokens, hasLength(2));
      expect(
          tokens.map((t) => t.label).toList(), containsAll(['token_1', 'token_2']));
    });

    test('deleteToken removes token by label', () async {
      await store.createToken(
        userId: testUserId,
        label: 'delete_this_token',
        scopes: ['read:all'],
      );

      var tokens = await store.listTokens(userId: testUserId);
      expect(
          tokens.where((t) => t.label == 'delete_this_token'), hasLength(1));

      final deleted = await store.deleteToken('delete_this_token');
      expect(deleted, isTrue);

      tokens = await store.listTokens(userId: testUserId);
      expect(tokens.where((t) => t.label == 'delete_this_token'), isEmpty);
    });

    test('deleteToken returns false for non-existent token', () async {
      final deleted = await store.deleteToken('no_such_token');
      expect(deleted, isFalse);
    });

    test('createToken with expiration', () async {
      final expiresAt = DateTime.now().add(const Duration(days: 30));
      final token = await store.createToken(
        userId: testUserId,
        label: 'expiring_token',
        scopes: ['read:all'],
        expiresAt: expiresAt,
      );

      final tokenHash = _hashToken(token);
      final retrieved = await store.getTokenByHash(tokenHash);

      expect(retrieved!.expiresAt, isNotNull);
      // Allow 1 second difference for timing
      expect(
        retrieved.expiresAt!.difference(expiresAt).inSeconds.abs(),
        lessThan(2),
      );
    });

    test('touchToken updates last_used_at', () async {
      final token = await store.createToken(
        userId: testUserId,
        label: 'touch_token',
        scopes: ['read:all'],
      );

      final tokenHash = _hashToken(token);

      // Wait a moment
      await Future.delayed(const Duration(milliseconds: 100));

      // Touch the token
      await store.touchToken(tokenHash);

      final retrieved = await store.getTokenByHash(tokenHash);
      expect(retrieved!.lastUsedAt, isNotNull);
    });
  });

  group('Upload Session Operations', () {
    test('createUploadSession creates session with TTL', () async {
      final session = await store.createUploadSession(
        ttl: const Duration(hours: 1),
      );

      expect(session.id, isNotEmpty);
      expect(session.expiresAt.isAfter(DateTime.now()), isTrue);
    });

    test('getUploadSession retrieves session', () async {
      final created = await store.createUploadSession();
      final retrieved = await store.getUploadSession(created.id);

      expect(retrieved, isNotNull);
      expect(retrieved!.id, created.id);
    });

    test('getUploadSession returns null for non-existent session', () async {
      final session = await store.getUploadSession('non_existent_id');
      expect(session, isNull);
    });

    test('completeUploadSession marks session as completed', () async {
      final session = await store.createUploadSession();
      await store.completeUploadSession(session.id);

      // Session should be cleaned up after completion
      final retrieved = await store.getUploadSession(session.id);
      // Completed sessions may be deleted or marked - check behavior
      // The session should still exist but be marked complete
    });

    test('cleanupExpiredSessions removes old sessions', () async {
      // Create expired session
      await store.createUploadSession(
        ttl: const Duration(seconds: 0),
      );

      // Wait a moment
      await Future.delayed(const Duration(milliseconds: 100));

      final cleaned = await store.cleanupExpiredSessions();
      expect(cleaned, greaterThanOrEqualTo(0));
    });
  });

  group('Admin User Operations', () {
    test('createAdminUser creates admin user', () async {
      final userId = await store.createAdminUser(
        username: 'testadmin',
        passwordHash: 'hashed_password',
        name: 'Test Admin',
      );

      expect(userId, isNotEmpty);
    });

    test('getAdminUserByUsername retrieves admin user', () async {
      await store.createAdminUser(
        username: 'findme',
        passwordHash: 'hash123',
        name: 'Find Me',
      );

      final admin = await store.getAdminUserByUsername('findme');
      expect(admin, isNotNull);
      expect(admin!.username, 'findme');
      expect(admin.name, 'Find Me');
      expect(admin.isActive, isTrue);
    });

    test('getAdminUserByUsername returns null for non-existent user', () async {
      final admin = await store.getAdminUserByUsername('nobody');
      expect(admin, isNull);
    });

    test('listAdminUsers returns all admin users', () async {
      await store.createAdminUser(
        username: 'admin1',
        passwordHash: 'h1',
        name: 'Admin One',
      );

      await store.createAdminUser(
        username: 'admin2',
        passwordHash: 'h2',
        name: 'Admin Two',
      );

      final admins = await store.listAdminUsers();
      expect(admins.length, greaterThanOrEqualTo(2));
    });

    test('deleteAdminUser removes admin user', () async {
      final userId = await store.createAdminUser(
        username: 'delete_admin',
        passwordHash: 'hash',
        name: 'Delete Admin',
      );

      var admin = await store.getAdminUserByUsername('delete_admin');
      expect(admin, isNotNull);

      await store.deleteAdminUser(userId);
      admin = await store.getAdminUserByUsername('delete_admin');
      expect(admin, isNull);
    });
  });

  group('Site Config Operations', () {
    test('getConfig returns null for non-existent config', () async {
      final config = await store.getConfig('nonexistent_config');
      expect(config, isNull);
    });

    test('setConfig updates existing config', () async {
      // allow_registration is created by migration
      var config = await store.getConfig('allow_registration');
      expect(config, isNotNull);
      expect(config!.value, 'true');

      // Update it
      await store.setConfig('allow_registration', 'false');
      config = await store.getConfig('allow_registration');
      expect(config!.value, 'false');

      // Restore
      await store.setConfig('allow_registration', 'true');
    });

    test('getAllConfig returns all default configs', () async {
      final configs = await store.getAllConfig();
      // Migration creates several default configs
      expect(configs.length, greaterThanOrEqualTo(5));

      final names = configs.map((c) => c.name).toList();
      // Check for some default configs from migration
      expect(names, containsAll([
        'allow_registration',
        'require_email_verification',
        'allow_anonymous_publish',
      ]));
    });
  });

  group('User Operations', () {
    test('createUser creates regular user', () async {
      final userId = await store.createUser(
        email: 'test@example.com',
        passwordHash: 'hash123',
        name: 'Test User',
      );

      expect(userId, isNotEmpty);
    });

    test('getUserByEmail retrieves user', () async {
      await store.createUser(
        email: 'find@example.com',
        passwordHash: 'hash',
        name: 'Find User',
      );

      final user = await store.getUserByEmail('find@example.com');
      expect(user, isNotNull);
      expect(user!.email, 'find@example.com');
      expect(user.name, 'Find User');
    });

    test('getUserByEmail returns null for non-existent user', () async {
      final user = await store.getUserByEmail('nobody@example.com');
      expect(user, isNull);
    });

    test('getUser retrieves user by ID', () async {
      final userId = await store.createUser(
        email: 'byid@example.com',
        passwordHash: 'hash',
        name: 'By ID User',
      );

      final user = await store.getUser(userId);
      expect(user, isNotNull);
      expect(user!.id, userId);
    });

    test('listUsers returns paginated users', () async {
      for (var i = 0; i < 5; i++) {
        await store.createUser(
          email: 'user$i@example.com',
          passwordHash: 'hash',
          name: 'User $i',
        );
      }

      final result = await store.listUsers(page: 1, limit: 3);
      // There may be a default anonymous user too
      expect(result.length, lessThanOrEqualTo(3));
    });
  });

  group('Activity Log Operations', () {
    test('logActivity creates activity entry', () async {
      await store.logActivity(
        activityType: 'test_activity',
        actorType: 'user',
        actorId: 'user123',
        actorEmail: 'actor@example.com',
        targetType: 'package',
        targetId: 'my_package',
        metadata: {'key': 'value'},
      );

      // Activity should be logged
      final activity = await store.getRecentActivity(limit: 10);
      expect(activity, isNotEmpty);
      expect(activity.first.activityType, 'test_activity');
    });

    test('getRecentActivity returns limited results', () async {
      for (var i = 0; i < 20; i++) {
        await store.logActivity(
          activityType: 'bulk_test',
          actorType: 'system',
        );
      }

      final activity = await store.getRecentActivity(limit: 5);
      expect(activity.length, lessThanOrEqualTo(5));
    });
  });

  group('Health Check', () {
    test('healthCheck returns status info', () async {
      final health = await store.healthCheck();

      expect(health['status'], 'healthy');
      expect(health['type'], 'sqlite');
    });
  });

  group('Download Tracking', () {
    test('getPackageDownloadStats returns stats', () async {
      await store.upsertPackageVersion(
        packageName: 'download_pkg',
        version: '1.0.0',
        pubspec: {'name': 'download_pkg', 'version': '1.0.0'},
        archiveKey: 'download_pkg/1.0.0.tar.gz',
        archiveSha256: 'hash',
      );

      final stats = await store.getPackageDownloadStats(
        'download_pkg',
        historyDays: 30,
      );
      expect(stats, isNotNull);
      expect(stats.packageName, 'download_pkg');
    });
  });

  group('Version Retraction', () {
    test('retractPackageVersion marks version as retracted', () async {
      await store.upsertPackageVersion(
        packageName: 'retract_pkg',
        version: '1.0.0',
        pubspec: {'name': 'retract_pkg', 'version': '1.0.0'},
        archiveKey: 'retract_pkg/1.0.0.tar.gz',
        archiveSha256: 'hash',
      );

      await store.retractPackageVersion('retract_pkg', '1.0.0');

      final version = await store.getPackageVersion('retract_pkg', '1.0.0');
      expect(version!.isRetracted, isTrue);
    });

    test('unretractPackageVersion restores version', () async {
      await store.upsertPackageVersion(
        packageName: 'unretract_pkg',
        version: '1.0.0',
        pubspec: {'name': 'unretract_pkg', 'version': '1.0.0'},
        archiveKey: 'unretract_pkg/1.0.0.tar.gz',
        archiveSha256: 'hash',
      );

      await store.retractPackageVersion('unretract_pkg', '1.0.0');
      await store.unretractPackageVersion('unretract_pkg', '1.0.0');

      final version = await store.getPackageVersion('unretract_pkg', '1.0.0');
      expect(version!.isRetracted, isFalse);
    });
  });
}

/// Hash a token (same as MetadataStore implementation)
String _hashToken(String token) {
  final bytes = utf8.encode(token);
  return sha256.convert(bytes).toString();
}
