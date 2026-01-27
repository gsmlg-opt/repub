import 'dart:io';

import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

void main() {
  group('Admin API Integration Tests', () {
    late MetadataStore metadata;
    late Config config;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('repub_admin_api_test_');

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
      );

      metadata = await MetadataStore.create(config);
      await metadata.runMigrations();
    });

    tearDown(() async {
      await metadata.close();
      await tempDir.delete(recursive: true);
    });

    group('User Management', () {
      test('can create a new user', () async {
        final userId = await metadata.createUser(
          email: 'test@example.com',
          passwordHash: 'hash123',
        );

        expect(userId, isNotEmpty);

        final user = await metadata.getUser(userId);
        expect(user, isNotNull);
        expect(user!.email, equals('test@example.com'));
        expect(user.isActive, isTrue);
      });

      test('can list all users', () async {
        // Create multiple users
        await metadata.createUser(
          email: 'user1@example.com',
          passwordHash: 'hash1',
        );
        await metadata.createUser(
          email: 'user2@example.com',
          passwordHash: 'hash2',
        );
        await metadata.createUser(
          email: 'user3@example.com',
          passwordHash: 'hash3',
        );

        final users = await metadata.listUsers(page: 1, limit: 10);

        expect(users.length, greaterThanOrEqualTo(3));
      });

      test('can paginate users', () async {
        // Create 5 users
        for (var i = 0; i < 5; i++) {
          await metadata.createUser(
            email: 'paginate$i@example.com',
            passwordHash: 'hash$i',
          );
        }

        // Get first page
        final page1 = await metadata.listUsers(page: 1, limit: 2);
        expect(page1.length, equals(2));

        // Get second page
        final page2 = await metadata.listUsers(page: 2, limit: 2);
        expect(page2.length, equals(2));

        // Ensure different users on each page
        expect(page1[0].id, isNot(equals(page2[0].id)));
      });

      test('can update user name', () async {
        final userId = await metadata.createUser(
          email: 'updatename@example.com',
          passwordHash: 'hash',
        );

        await metadata.updateUser(userId, name: 'New Name');

        final user = await metadata.getUser(userId);
        expect(user!.name, equals('New Name'));
      });

      test('can deactivate user', () async {
        final userId = await metadata.createUser(
          email: 'deactivate@example.com',
          passwordHash: 'hash',
        );

        await metadata.updateUser(userId, isActive: false);

        final user = await metadata.getUser(userId);
        expect(user!.isActive, isFalse);
      });

      test('can delete user', () async {
        final userId = await metadata.createUser(
          email: 'todelete@example.com',
          passwordHash: 'hash',
        );

        await metadata.deleteUser(userId);

        final user = await metadata.getUser(userId);
        expect(user, isNull);
      });

      test('deleting user also deletes their tokens', () async {
        final userId = await metadata.createUser(
          email: 'withtokens@example.com',
          passwordHash: 'hash',
        );

        // Create some tokens
        await metadata.createToken(
          userId: userId,
          label: 'Token 1',
          scopes: ['publish:all'],
        );
        await metadata.createToken(
          userId: userId,
          label: 'Token 2',
          scopes: ['read:all'],
        );

        // Verify tokens exist
        var tokens = await metadata.listTokens(userId: userId);
        expect(tokens.length, equals(2));

        // Delete user
        await metadata.deleteUser(userId);

        // Verify tokens are gone
        tokens = await metadata.listTokens(userId: userId);
        expect(tokens.isEmpty, isTrue);
      });
    });

    group('Config Management', () {
      test('can get pre-seeded config value', () async {
        // site_config table is pre-seeded with default values
        final config = await metadata.getConfig('allow_registration');
        expect(config, isNotNull);
        expect(config!.name, equals('allow_registration'));
      });

      test('can update existing config', () async {
        // Update allow_registration which is pre-seeded
        await metadata.setConfig('allow_registration', 'false');

        final config = await metadata.getConfig('allow_registration');
        expect(config?.value, equals('false'));
      });

      test('can list all config entries', () async {
        final configs = await metadata.getAllConfig();

        // Default configs from migration
        expect(configs.any((c) => c.name == 'allow_registration'), isTrue);
        expect(configs.any((c) => c.name == 'session_ttl_hours'), isTrue);
        expect(configs.isNotEmpty, isTrue);
      });

      test('returns null for non-existent config', () async {
        final config = await metadata.getConfig('non_existent_key_xyz');
        expect(config, isNull);
      });
    });

    group('Admin User Management', () {
      test('can create admin user', () async {
        final adminId = await metadata.createAdminUser(
          username: 'testadmin',
          passwordHash: 'hash123',
        );

        expect(adminId, isNotEmpty);

        final admin = await metadata.getAdminUser(adminId);
        expect(admin, isNotNull);
        expect(admin!.username, equals('testadmin'));
        expect(admin.isActive, isTrue);
      });

      test('can list admin users', () async {
        await metadata.createAdminUser(
          username: 'admin1',
          passwordHash: 'hash1',
        );
        await metadata.createAdminUser(
          username: 'admin2',
          passwordHash: 'hash2',
        );

        final admins = await metadata.listAdminUsers(page: 1, limit: 10);

        expect(admins.length, greaterThanOrEqualTo(2));
      });

      test('admin user can have mustChangePassword flag', () async {
        final adminId = await metadata.createAdminUser(
          username: 'mustchange',
          passwordHash: 'hash',
          mustChangePassword: true,
        );

        final admin = await metadata.getAdminUser(adminId);
        expect(admin!.mustChangePassword, isTrue);
      });

      test('can update admin user', () async {
        final adminId = await metadata.createAdminUser(
          username: 'toupdate',
          passwordHash: 'hash',
        );

        await metadata.updateAdminUser(
          adminId,
          name: 'Updated Name',
        );

        final admin = await metadata.getAdminUser(adminId);
        expect(admin!.name, equals('Updated Name'));
      });
    });

    group('Token Management', () {
      late String userId;

      setUp(() async {
        userId = await metadata.createUser(
          email: 'tokentest@example.com',
          passwordHash: 'hash',
        );
      });

      test('can create token with scopes', () async {
        final token = await metadata.createToken(
          userId: userId,
          label: 'Test Token',
          scopes: ['publish:all', 'read:all'],
        );

        expect(token, isNotEmpty);

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.length, equals(1));
        expect(tokens.first.label, equals('Test Token'));
        expect(tokens.first.scopes, contains('publish:all'));
        expect(tokens.first.scopes, contains('read:all'));
      });

      test('can create package-specific publish token', () async {
        final token = await metadata.createToken(
          userId: userId,
          label: 'Package Token',
          scopes: ['publish:pkg:my_package'],
        );

        expect(token, isNotEmpty);

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.first.canPublish('my_package'), isTrue);
        expect(tokens.first.canPublish('other_package'), isFalse);
      });

      test('token has correct permissions', () async {
        await metadata.createToken(
          userId: userId,
          label: 'Admin Token',
          scopes: ['admin'],
        );

        final tokens = await metadata.listTokens(userId: userId);
        expect(tokens.first.isAdmin, isTrue);
        expect(tokens.first.canPublishAll, isTrue);
      });
    });

    group('Statistics', () {
      test('can get admin stats', () async {
        // Create some test data
        await metadata.createUser(
          email: 'statsuser@example.com',
          passwordHash: 'hash',
        );

        final stats = await metadata.getAdminStats();

        expect(stats, isNotNull);
        expect(stats.totalPackages, greaterThanOrEqualTo(0));
        expect(stats.localPackages, greaterThanOrEqualTo(0));
        expect(stats.cachedPackages, greaterThanOrEqualTo(0));
        expect(stats.totalVersions, greaterThanOrEqualTo(0));
      });
    });
  });
}
