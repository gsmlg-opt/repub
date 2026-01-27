import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

void main() {
  late MetadataStore metadata;

  setUp(() async {
    metadata = SqliteMetadataStore.open(':memory:');
    await metadata.runMigrations();
  });

  tearDown(() async {
    await metadata.close();
  });

  group('Package Ownership Transfer', () {
    test('transfers ownership to existing user', () async {
      // Create a user
      final userId = await metadata.createUser(
        email: 'owner@example.com',
        name: 'Original Owner',
      );

      // Create a new user to transfer to
      final newUserId = await metadata.createUser(
        email: 'newowner@example.com',
        name: 'New Owner',
      );

      // Create a package with original owner
      await metadata.upsertPackageVersion(
        packageName: 'test_package',
        version: '1.0.0',
        pubspec: {'name': 'test_package', 'version': '1.0.0'},
        archiveKey: 'packages/test_package-1.0.0.tar.gz',
        archiveSha256: 'abc123',
        ownerId: userId,
      );

      // Verify original ownership
      var pkg = await metadata.getPackage('test_package');
      expect(pkg, isNotNull);
      expect(pkg!.ownerId, equals(userId));

      // Transfer ownership
      final success =
          await metadata.transferPackageOwnership('test_package', newUserId);
      expect(success, isTrue);

      // Verify new ownership
      pkg = await metadata.getPackage('test_package');
      expect(pkg, isNotNull);
      expect(pkg!.ownerId, equals(newUserId));
    });

    test('transfers ownership to anonymous user', () async {
      // Create a user
      final userId = await metadata.createUser(
        email: 'owner@example.com',
        name: 'Original Owner',
      );

      // Create a package with original owner
      await metadata.upsertPackageVersion(
        packageName: 'test_package',
        version: '1.0.0',
        pubspec: {'name': 'test_package', 'version': '1.0.0'},
        archiveKey: 'packages/test_package-1.0.0.tar.gz',
        archiveSha256: 'abc123',
        ownerId: userId,
      );

      // Transfer to anonymous
      final success = await metadata.transferPackageOwnership(
        'test_package',
        User.anonymousId,
      );
      expect(success, isTrue);

      // Verify anonymous ownership
      final pkg = await metadata.getPackage('test_package');
      expect(pkg, isNotNull);
      expect(pkg!.ownerId, equals(User.anonymousId));
    });

    test('fails to transfer to non-existent user', () async {
      // Create a package
      await metadata.upsertPackageVersion(
        packageName: 'test_package',
        version: '1.0.0',
        pubspec: {'name': 'test_package', 'version': '1.0.0'},
        archiveKey: 'packages/test_package-1.0.0.tar.gz',
        archiveSha256: 'abc123',
      );

      // Try to transfer to non-existent user
      final success = await metadata.transferPackageOwnership(
        'test_package',
        'non-existent-user-id',
      );
      expect(success, isFalse);
    });

    test('fails to transfer non-existent package', () async {
      // Create a user to transfer to
      final userId = await metadata.createUser(
        email: 'user@example.com',
        name: 'User',
      );

      // Try to transfer non-existent package
      final success = await metadata.transferPackageOwnership(
        'non_existent_package',
        userId,
      );
      expect(success, isFalse);
    });

    test('transfer updates publish permissions', () async {
      // Create original owner
      final originalOwner = await metadata.createUser(
        email: 'original@example.com',
        name: 'Original Owner',
      );

      // Create new owner
      final newOwner = await metadata.createUser(
        email: 'new@example.com',
        name: 'New Owner',
      );

      // Create a package with original owner
      await metadata.upsertPackageVersion(
        packageName: 'test_package',
        version: '1.0.0',
        pubspec: {'name': 'test_package', 'version': '1.0.0'},
        archiveKey: 'packages/test_package-1.0.0.tar.gz',
        archiveSha256: 'abc123',
        ownerId: originalOwner,
      );

      // Check permissions before transfer
      var pkg = await metadata.getPackage('test_package');
      expect(pkg!.canPublish(originalOwner), isTrue);
      expect(pkg.canPublish(newOwner), isFalse);

      // Transfer ownership
      await metadata.transferPackageOwnership('test_package', newOwner);

      // Check permissions after transfer
      pkg = await metadata.getPackage('test_package');
      expect(pkg!.canPublish(originalOwner), isFalse);
      expect(pkg.canPublish(newOwner), isTrue);
    });

    test('transfer from anonymous to specific user', () async {
      // Create a package without owner (defaults to null or anonymous)
      await metadata.upsertPackageVersion(
        packageName: 'legacy_package',
        version: '1.0.0',
        pubspec: {'name': 'legacy_package', 'version': '1.0.0'},
        archiveKey: 'packages/legacy_package-1.0.0.tar.gz',
        archiveSha256: 'abc123',
        // No ownerId - legacy/unowned package
      );

      // Create a user
      final userId = await metadata.createUser(
        email: 'claimer@example.com',
        name: 'Package Claimer',
      );

      // Transfer to user
      final success =
          await metadata.transferPackageOwnership('legacy_package', userId);
      expect(success, isTrue);

      // Verify ownership
      final pkg = await metadata.getPackage('legacy_package');
      expect(pkg!.ownerId, equals(userId));
      expect(pkg.canPublish(userId), isTrue);
    });
  });
}
