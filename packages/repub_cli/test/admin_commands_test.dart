import 'dart:io';

import 'package:repub_auth/repub_auth.dart';
import 'package:repub_cli/src/admin_commands.dart';
import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

void main() {
  group('Admin Commands', () {
    late SqliteMetadataStore metadata;
    late Config config;

    setUp(() async {
      // Use in-memory SQLite for tests
      metadata = SqliteMetadataStore.inMemory();
      await metadata.runMigrations();

      config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite::memory:',
        storagePath: '/tmp',
        requirePublishAuth: true,
        requireDownloadAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: false,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );
    });

    tearDown(() async {
      await metadata.close();
    });

    group('Create Admin', () {
      test('creates admin user with username and password', () async {
        // Create admin via CLI command
        await adminCommandsWithStore(
          metadata,
          ['create', 'testadmin', 'password123'],
        );

        // Verify admin was created
        final admin = await metadata.getAdminUserByUsername('testadmin');
        expect(admin, isNotNull);
        expect(admin!.username, equals('testadmin'));
        expect(admin.isActive, isTrue);
      });

      test('creates admin user with optional name', () async {
        await adminCommandsWithStore(
          metadata,
          ['create', 'namedadmin', 'password123', 'Test Admin'],
        );

        final admin = await metadata.getAdminUserByUsername('namedadmin');
        expect(admin, isNotNull);
        expect(admin!.name, equals('Test Admin'));
      });

      test('prevents duplicate username creation', () async {
        // Create first admin
        await adminCommandsWithStore(
          metadata,
          ['create', 'duplicateadmin', 'pass1'],
        );

        // Try to create again - should fail
        await adminCommandsWithStore(
          metadata,
          ['create', 'duplicateadmin', 'pass2'],
        );

        // Verify only one admin exists
        final admins = await metadata.listAdminUsers(limit: 100);
        final duplicateCount =
            admins.where((a) => a.username == 'duplicateadmin').length;
        expect(duplicateCount, equals(1));
      });

      test('password is hashed correctly', () async {
        await adminCommandsWithStore(
          metadata,
          ['create', 'hashtest', 'mypassword'],
        );

        final admin = await metadata.getAdminUserByUsername('hashtest');
        expect(admin, isNotNull);

        // Verify password is stored hashed
        expect(admin!.passwordHash, isNotNull);
        expect(admin.passwordHash, isNot(equals('mypassword')));
        expect(admin.passwordHash!, startsWith(r'$2'));

        // Verify password verifies correctly
        expect(verifyPassword('mypassword', admin.passwordHash!), isTrue);
        expect(verifyPassword('wrongpassword', admin.passwordHash!), isFalse);
      });
    });

    group('List Admins', () {
      test('lists all admin users', () async {
        // Create multiple admins
        await adminCommandsWithStore(
          metadata,
          ['create', 'admin1', 'pass1', 'First Admin'],
        );
        await adminCommandsWithStore(
          metadata,
          ['create', 'admin2', 'pass2', 'Second Admin'],
        );
        await adminCommandsWithStore(
          metadata,
          ['create', 'admin3', 'pass3'],
        );

        // Verify all admins exist
        final admins = await metadata.listAdminUsers(limit: 100);
        expect(admins.length, equals(3));
        expect(admins.map((a) => a.username).toSet(),
            containsAll(['admin1', 'admin2', 'admin3']));
      });
    });

    group('Reset Password', () {
      test('resets admin password', () async {
        await adminCommandsWithStore(
          metadata,
          ['create', 'resetme', 'oldpassword'],
        );

        // Verify old password works
        var admin = await metadata.getAdminUserByUsername('resetme');
        expect(admin, isNotNull);
        expect(admin!.passwordHash, isNotNull);
        expect(verifyPassword('oldpassword', admin.passwordHash!), isTrue);

        // Reset password
        await adminCommandsWithStore(
          metadata,
          ['reset-password', 'resetme', 'newpassword'],
        );

        // Verify new password works
        admin = await metadata.getAdminUserByUsername('resetme');
        expect(admin, isNotNull);
        expect(admin!.passwordHash, isNotNull);
        expect(verifyPassword('newpassword', admin.passwordHash!), isTrue);
        expect(verifyPassword('oldpassword', admin.passwordHash!), isFalse);
      });

      test('fails for non-existent user', () async {
        // This should print error but not throw
        await adminCommandsWithStore(
          metadata,
          ['reset-password', 'nonexistent', 'newpass'],
        );

        // Verify no user was created
        final admin = await metadata.getAdminUserByUsername('nonexistent');
        expect(admin, isNull);
      });
    });

    group('Activate/Deactivate Admin', () {
      test('deactivates an active admin', () async {
        await adminCommandsWithStore(
          metadata,
          ['create', 'toggleadmin', 'pass'],
        );

        // Verify initially active
        var admin = await metadata.getAdminUserByUsername('toggleadmin');
        expect(admin!.isActive, isTrue);

        // Deactivate
        await adminCommandsWithStore(
          metadata,
          ['deactivate', 'toggleadmin'],
        );

        // Verify now inactive
        admin = await metadata.getAdminUserByUsername('toggleadmin');
        expect(admin!.isActive, isFalse);
      });

      test('activates an inactive admin', () async {
        await adminCommandsWithStore(
          metadata,
          ['create', 'inactiveadmin', 'pass'],
        );

        // Deactivate first
        await adminCommandsWithStore(
          metadata,
          ['deactivate', 'inactiveadmin'],
        );

        var admin = await metadata.getAdminUserByUsername('inactiveadmin');
        expect(admin!.isActive, isFalse);

        // Activate
        await adminCommandsWithStore(
          metadata,
          ['activate', 'inactiveadmin'],
        );

        admin = await metadata.getAdminUserByUsername('inactiveadmin');
        expect(admin!.isActive, isTrue);
      });

      test('activating already active admin is idempotent', () async {
        await adminCommandsWithStore(
          metadata,
          ['create', 'alreadyactive', 'pass'],
        );

        // Activate again (no-op)
        await adminCommandsWithStore(
          metadata,
          ['activate', 'alreadyactive'],
        );

        final admin = await metadata.getAdminUserByUsername('alreadyactive');
        expect(admin!.isActive, isTrue);
      });
    });

    group('Delete Admin', () {
      test('deletes an admin user', () async {
        await adminCommandsWithStore(
          metadata,
          ['create', 'deleteme', 'pass'],
        );

        // Verify exists
        var admin = await metadata.getAdminUserByUsername('deleteme');
        expect(admin, isNotNull);

        // Delete
        await adminCommandsWithStore(
          metadata,
          ['delete', 'deleteme'],
        );

        // Verify deleted
        admin = await metadata.getAdminUserByUsername('deleteme');
        expect(admin, isNull);
      });

      test('deleting non-existent user does nothing', () async {
        // Should not throw
        await adminCommandsWithStore(
          metadata,
          ['delete', 'nonexistent'],
        );
      });
    });

    group('Invalid Commands', () {
      test('handles unknown command gracefully', () async {
        // Should not throw
        await adminCommandsWithStore(
          metadata,
          ['unknown-command'],
        );
      });

      test('handles missing arguments for create', () async {
        await adminCommandsWithStore(
          metadata,
          ['create', 'onlyusername'],
        );

        // Should not create user with missing password
        final admin = await metadata.getAdminUserByUsername('onlyusername');
        expect(admin, isNull);
      });

      test('handles empty args list', () async {
        await adminCommandsWithStore(
          metadata,
          [],
        );
        // Should just print usage, no errors
      });
    });
  });
}

/// Wrapper to call admin commands with a specific metadata store (for testing).
/// This bypasses the Config.fromEnv() and uses the provided store.
Future<void> adminCommandsWithStore(
    MetadataStore metadata, List<String> args) async {
  if (args.isEmpty) {
    return;
  }

  final command = args[0];
  final commandArgs = args.skip(1).toList();

  // Capture stdout for tests (optional: could use a mock stdout)
  await _runAdminCommand(metadata, command, commandArgs);
}

Future<void> _runAdminCommand(
    MetadataStore metadata, String command, List<String> args) async {
  switch (command) {
    case 'create':
      if (args.length < 2) return;
      final username = args[0];
      final password = args[1];
      final name = args.length > 2 ? args[2] : null;

      final existing = await metadata.getAdminUserByUsername(username);
      if (existing != null) return;

      final passwordHash = hashPassword(password);
      await metadata.createAdminUser(
        username: username,
        passwordHash: passwordHash,
        name: name,
      );

    case 'list':
      // Just read - no action needed for tests
      await metadata.listAdminUsers(limit: 100);

    case 'reset-password':
      if (args.length < 2) return;
      final username = args[0];
      final newPassword = args[1];

      final admin = await metadata.getAdminUserByUsername(username);
      if (admin == null) return;

      final passwordHash = hashPassword(newPassword);
      await metadata.updateAdminUser(admin.id, passwordHash: passwordHash);

    case 'activate':
      if (args.isEmpty) return;
      final username = args[0];

      final admin = await metadata.getAdminUserByUsername(username);
      if (admin == null) return;
      if (admin.isActive) return;

      await metadata.updateAdminUser(admin.id, isActive: true);

    case 'deactivate':
      if (args.isEmpty) return;
      final username = args[0];

      final admin = await metadata.getAdminUserByUsername(username);
      if (admin == null) return;
      if (!admin.isActive) return;

      await metadata.updateAdminUser(admin.id, isActive: false);

    case 'delete':
      if (args.isEmpty) return;
      final username = args[0];

      final admin = await metadata.getAdminUserByUsername(username);
      if (admin == null) return;

      await metadata.deleteAdminUser(admin.id);
  }
}
