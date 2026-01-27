import 'dart:convert';
import 'dart:io';

import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

void main() {
  late SqliteMetadataStore store;
  late BackupManager backupManager;
  late Directory tempDir;

  setUp(() async {
    // Create an in-memory SQLite store for testing
    store = SqliteMetadataStore.open(':memory:');
    store.runMigrations();
    backupManager = BackupManager(store);
    tempDir = await Directory.systemTemp.createTemp('backup_test_');
  });

  tearDown(() async {
    store.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('BackupData', () {
    test('toJson serializes correctly', () {
      final backup = BackupData(
        formatVersion: 1,
        createdAt: DateTime.utc(2026, 1, 28),
        databaseType: 'sqlite',
        packages: [
          {'name': 'test_pkg', 'description': 'Test package'}
        ],
        packageVersions: [
          {'package_name': 'test_pkg', 'version': '1.0.0'}
        ],
        users: [
          {'email': 'user@test.com'}
        ],
        adminUsers: [
          {'username': 'admin'}
        ],
        authTokens: [
          {'hash': 'abc123'}
        ],
        activityLog: [
          {'type': 'user_registered'}
        ],
      );

      final json = backup.toJson();

      expect(json['formatVersion'], 1);
      expect(json['createdAt'], '2026-01-28T00:00:00.000Z');
      expect(json['databaseType'], 'sqlite');
      expect(json['data']['packages'], hasLength(1));
      expect(json['data']['packageVersions'], hasLength(1));
      expect(json['data']['users'], hasLength(1));
      expect(json['data']['adminUsers'], hasLength(1));
      expect(json['data']['authTokens'], hasLength(1));
      expect(json['data']['activityLog'], hasLength(1));
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'formatVersion': 1,
        'createdAt': '2026-01-28T12:00:00.000Z',
        'databaseType': 'postgresql',
        'data': {
          'packages': [
            {'name': 'my_pkg'}
          ],
          'packageVersions': [],
          'users': [],
          'adminUsers': [],
          'authTokens': [],
          'activityLog': [],
        }
      };

      final backup = BackupData.fromJson(json);

      expect(backup.formatVersion, 1);
      expect(backup.createdAt.toIso8601String(), '2026-01-28T12:00:00.000Z');
      expect(backup.databaseType, 'postgresql');
      expect(backup.packages, hasLength(1));
      expect(backup.packages[0]['name'], 'my_pkg');
    });

    test('summary returns correct counts', () {
      final backup = BackupData(
        formatVersion: 1,
        createdAt: DateTime.now(),
        databaseType: 'sqlite',
        packages: [
          {'name': 'pkg1'},
          {'name': 'pkg2'},
          {'name': 'pkg3'}
        ],
        packageVersions: [
          {'version': '1.0.0'},
          {'version': '2.0.0'}
        ],
        users: [
          {'email': 'user1@test.com'}
        ],
        adminUsers: [],
        authTokens: [
          {'hash': 'h1'},
          {'hash': 'h2'},
          {'hash': 'h3'},
          {'hash': 'h4'}
        ],
        activityLog: [
          {'type': 'activity1'},
          {'type': 'activity2'}
        ],
      );

      final summary = backup.summary;

      expect(summary['packages'], 3);
      expect(summary['packageVersions'], 2);
      expect(summary['users'], 1);
      expect(summary['adminUsers'], 0);
      expect(summary['authTokens'], 4);
      expect(summary['activityLog'], 2);
    });
  });

  group('BackupManager', () {
    test('createBackup creates backup from fresh database', () async {
      final backup = await backupManager.createBackup();

      expect(backup.formatVersion, backupFormatVersion);
      expect(backup.databaseType, 'sqlite');
      expect(backup.packages, isEmpty);
      expect(backup.packageVersions, isEmpty);
      // Database has default anonymous user from migrations
      expect(backup.users, hasLength(1));
      expect(backup.users[0]['email'], 'anonymous@localhost');
      expect(backup.adminUsers, isEmpty);
      expect(backup.authTokens, isEmpty);
      expect(backup.activityLog, isEmpty);
    });

    test('createBackup includes packages and versions', () async {
      // Create a package using upsertPackageVersion
      await store.upsertPackageVersion(
        packageName: 'test_package',
        version: '1.0.0',
        pubspec: {'name': 'test_package', 'version': '1.0.0'},
        archiveKey: 'test_package/1.0.0.tar.gz',
        archiveSha256: 'abc123',
      );

      final backup = await backupManager.createBackup();

      expect(backup.packages, hasLength(1));
      expect(backup.packages[0]['name'], 'test_package');
      expect(backup.packageVersions, hasLength(1));
      expect(backup.packageVersions[0]['version'], '1.0.0');
    });

    test('createBackup includes users', () async {
      await store.createUser(
        email: 'user@test.com',
        name: 'Test User',
        passwordHash: 'hash123',
      );

      final backup = await backupManager.createBackup();

      // Should include the new user plus the default anonymous user
      expect(backup.users, hasLength(2));
      expect(backup.users.any((u) => u['email'] == 'user@test.com'), isTrue);
    });

    test('createBackup includes admin users', () async {
      await store.createAdminUser(
        username: 'admin',
        passwordHash: 'adminhash',
      );

      final backup = await backupManager.createBackup();

      expect(backup.adminUsers, hasLength(1));
      expect(backup.adminUsers[0]['username'], 'admin');
    });

    test('createBackup includes auth tokens', () async {
      const testUserId = 'test-user-id-123';

      await store.createToken(
        userId: testUserId,
        label: 'Test Token',
        scopes: ['admin'],
      );

      final backup = await backupManager.createBackup();

      expect(backup.authTokens, hasLength(1));
      expect(backup.authTokens[0]['label'], 'Test Token');
    });

    test('createBackup includes activity log', () async {
      await store.logActivity(
        activityType: 'user_registered',
        actorType: 'system',
        actorId: 'test',
        targetType: 'user',
        targetId: 'user123',
      );

      final backup = await backupManager.createBackup();

      expect(backup.activityLog, hasLength(1));
      expect(backup.activityLog[0]['activity_type'], 'user_registered');
    });

    test('exportToFile creates valid JSON file', () async {
      // Add some data
      await store.upsertPackageVersion(
        packageName: 'export_test',
        version: '1.0.0',
        pubspec: {'name': 'export_test', 'version': '1.0.0'},
        archiveKey: 'export_test/1.0.0.tar.gz',
        archiveSha256: 'hash',
      );

      final filePath = '${tempDir.path}/backup.json';
      await backupManager.exportToFile(filePath);

      final file = File(filePath);
      expect(await file.exists(), isTrue);

      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;

      expect(json['formatVersion'], backupFormatVersion);
      expect(json['databaseType'], 'sqlite');
      expect(json['data']['packages'], hasLength(1));
    });

    test('importFromFile dry run returns summary without importing', () async {
      // Create a backup file manually
      final backupJson = {
        'formatVersion': 1,
        'createdAt': '2026-01-28T00:00:00.000Z',
        'databaseType': 'sqlite',
        'data': {
          'packages': [
            {'name': 'imported_pkg', 'description': 'Test'}
          ],
          'packageVersions': [],
          'users': [],
          'adminUsers': [],
          'authTokens': [],
          'activityLog': [],
        }
      };

      final filePath = '${tempDir.path}/import_dry.json';
      await File(filePath).writeAsString(jsonEncode(backupJson));

      final summary = await backupManager.importFromFile(filePath, dryRun: true);

      expect(summary['packages'], 1);

      // Verify nothing was actually imported
      final packages = await store.listPackages();
      expect(packages.packages, isEmpty);
    });

    test('importFromFile imports data correctly', () async {
      // Create a backup file with data
      final backupJson = {
        'formatVersion': 1,
        'createdAt': '2026-01-28T00:00:00.000Z',
        'databaseType': 'sqlite',
        'data': {
          'packages': [
            {
              'name': 'imported_pkg',
              'description': 'Imported package',
              'created_at': '2026-01-28T00:00:00.000Z',
              'updated_at': '2026-01-28T00:00:00.000Z',
              'is_discontinued': 0,
              'is_upstream_cache': 0,
            }
          ],
          'packageVersions': [
            {
              'id': 100,
              'package_name': 'imported_pkg',
              'version': '1.0.0',
              'pubspec_json': jsonEncode({
                'name': 'imported_pkg',
                'version': '1.0.0',
                'description': 'Imported package',
              }),
              'archive_key': 'imported_pkg/1.0.0.tar.gz',
              'archive_sha256': 'abc123',
              'published_at': '2026-01-28 00:00:00',
            }
          ],
          'users': [
            {
              'id': 'user-123',
              'email': 'imported@test.com',
              'name': 'Imported User',
              'password_hash': 'hash',
              'is_active': 1,
              'created_at': '2026-01-28T00:00:00.000Z',
            }
          ],
          'adminUsers': [
            {
              'id': 'admin-123',
              'username': 'imported_admin',
              'password_hash': 'adminhash',
              'created_at': '2026-01-28T00:00:00.000Z',
              'login_count': 0,
              'must_change_password': 0,
            }
          ],
          'authTokens': [],
          'activityLog': [],
        }
      };

      final filePath = '${tempDir.path}/import_full.json';
      await File(filePath).writeAsString(jsonEncode(backupJson));

      await backupManager.importFromFile(filePath);

      // Verify packages were imported
      final packages = await store.listPackages();
      expect(packages.packages, hasLength(1));
      expect(packages.packages[0].package.name, 'imported_pkg');

      // Verify users were imported (now includes anonymous user + imported)
      final user = await store.getUserByEmail('imported@test.com');
      expect(user, isNotNull);
      expect(user!.name, 'Imported User');

      // Verify admin users were imported
      final admin = await store.getAdminUserByUsername('imported_admin');
      expect(admin, isNotNull);
    });

    test('importFromFile throws on missing file', () async {
      final filePath = '${tempDir.path}/nonexistent.json';

      expect(
        () => backupManager.importFromFile(filePath),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'message', contains('not found'))),
      );
    });

    test('importFromFile throws on newer format version', () async {
      final backupJson = {
        'formatVersion': 999,
        'createdAt': '2026-01-28T00:00:00.000Z',
        'databaseType': 'sqlite',
        'data': {
          'packages': [],
          'packageVersions': [],
          'users': [],
          'adminUsers': [],
          'authTokens': [],
          'activityLog': [],
        }
      };

      final filePath = '${tempDir.path}/future_backup.json';
      await File(filePath).writeAsString(jsonEncode(backupJson));

      expect(
        () => backupManager.importFromFile(filePath),
        throwsA(isA<BackupException>()
            .having((e) => e.message, 'message', contains('newer'))),
      );
    });

    test('roundtrip export and import preserves data', () async {
      // Create test data
      await store.upsertPackageVersion(
        packageName: 'roundtrip_pkg',
        version: '1.0.0',
        pubspec: {
          'name': 'roundtrip_pkg',
          'version': '1.0.0',
          'description': 'Roundtrip test',
        },
        archiveKey: 'roundtrip_pkg/1.0.0.tar.gz',
        archiveSha256: 'hash',
      );

      const testUserId = 'roundtrip-user-id';

      await store.createToken(
        userId: testUserId,
        label: 'Roundtrip Token',
        scopes: ['publish:all'],
      );

      await store.createAdminUser(
        username: 'roundtrip_admin',
        passwordHash: 'adminhash',
      );

      await store.logActivity(
        activityType: 'package_published',
        actorType: 'user',
        actorId: testUserId,
        targetType: 'package',
        targetId: 'roundtrip_pkg',
      );

      // Export
      final exportPath = '${tempDir.path}/roundtrip_backup.json';
      await backupManager.exportToFile(exportPath);

      // Create new empty store
      final newStore = SqliteMetadataStore.open(':memory:');
      newStore.runMigrations();
      final newBackupManager = BackupManager(newStore);

      // Import into new store
      await newBackupManager.importFromFile(exportPath);

      // Verify all data was preserved
      final packages = await newStore.listPackages();
      expect(packages.packages, hasLength(1));
      expect(packages.packages[0].package.name, 'roundtrip_pkg');

      final importedAdmin =
          await newStore.getAdminUserByUsername('roundtrip_admin');
      expect(importedAdmin, isNotNull);

      final activities = await newStore.getRecentActivity(limit: 10);
      expect(activities, hasLength(1));

      newStore.close();
    });
  });

  group('BackupException', () {
    test('toString includes message', () {
      final exception = BackupException('Test error message');
      expect(exception.toString(), 'BackupException: Test error message');
    });
  });
}
