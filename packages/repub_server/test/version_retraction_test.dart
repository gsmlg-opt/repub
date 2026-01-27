import 'package:test/test.dart';
import 'package:repub_storage/repub_storage.dart';

void main() {
  late MetadataStore metadata;

  setUp(() async {
    // Create in-memory SQLite database for each test
    metadata = SqliteMetadataStore.open(':memory:');
    await metadata.runMigrations();

    // Create a test package with multiple versions
    await metadata.upsertPackageVersion(
      packageName: 'test_package',
      version: '1.0.0',
      pubspec: {'name': 'test_package', 'version': '1.0.0'},
      archiveKey: 'test/test_package-1.0.0.tar.gz',
      archiveSha256: 'abc123',
    );
    await metadata.upsertPackageVersion(
      packageName: 'test_package',
      version: '1.1.0',
      pubspec: {'name': 'test_package', 'version': '1.1.0'},
      archiveKey: 'test/test_package-1.1.0.tar.gz',
      archiveSha256: 'def456',
    );
  });

  tearDown(() async {
    await metadata.close();
  });

  group('Version Retraction', () {
    test('retractPackageVersion marks version as retracted', () async {
      final success = await metadata.retractPackageVersion(
        'test_package',
        '1.0.0',
      );

      expect(success, true);

      final version = await metadata.getPackageVersion('test_package', '1.0.0');
      expect(version, isNotNull);
      expect(version!.isRetracted, true);
      expect(version.retractedAt, isNotNull);
      expect(version.retractionMessage, isNull);
    });

    test('retractPackageVersion with message stores message', () async {
      const message = 'Security vulnerability - upgrade immediately';
      final success = await metadata.retractPackageVersion(
        'test_package',
        '1.0.0',
        message: message,
      );

      expect(success, true);

      final version = await metadata.getPackageVersion('test_package', '1.0.0');
      expect(version, isNotNull);
      expect(version!.isRetracted, true);
      expect(version.retractedAt, isNotNull);
      expect(version.retractionMessage, message);
    });

    test('retractPackageVersion returns false for non-existent version',
        () async {
      final success = await metadata.retractPackageVersion(
        'test_package',
        '99.99.99',
      );

      expect(success, false);
    });

    test('unretractPackageVersion clears retraction', () async {
      // First retract
      await metadata.retractPackageVersion(
        'test_package',
        '1.0.0',
        message: 'Test message',
      );

      // Then unretract
      final success = await metadata.unretractPackageVersion(
        'test_package',
        '1.0.0',
      );

      expect(success, true);

      final version = await metadata.getPackageVersion('test_package', '1.0.0');
      expect(version, isNotNull);
      expect(version!.isRetracted, false);
      expect(version.retractedAt, isNull);
      expect(version.retractionMessage, isNull);
    });

    test('unretractPackageVersion returns false for non-existent version',
        () async {
      final success = await metadata.unretractPackageVersion(
        'test_package',
        '99.99.99',
      );

      expect(success, false);
    });

    test('getPackageVersions includes retraction info', () async {
      await metadata.retractPackageVersion(
        'test_package',
        '1.0.0',
        message: 'Known issue',
      );

      final versions = await metadata.getPackageVersions('test_package');
      expect(versions.length, 2);

      final retractedVersion = versions.firstWhere((v) => v.version == '1.0.0');
      expect(retractedVersion.isRetracted, true);
      expect(retractedVersion.retractionMessage, 'Known issue');

      final normalVersion = versions.firstWhere((v) => v.version == '1.1.0');
      expect(normalVersion.isRetracted, false);
      expect(normalVersion.retractionMessage, isNull);
    });

    test('getPackageInfo latest excludes retracted versions', () async {
      // Retract the newer version
      await metadata.retractPackageVersion('test_package', '1.1.0');

      final info = await metadata.getPackageInfo('test_package');
      expect(info, isNotNull);
      expect(info!.latest, isNotNull);
      expect(info.latest!.version, '1.0.0'); // Should fall back to 1.0.0
    });

    test('getPackageInfo latest returns retracted if all versions retracted',
        () async {
      // Retract all versions
      await metadata.retractPackageVersion('test_package', '1.0.0');
      await metadata.retractPackageVersion('test_package', '1.1.0');

      final info = await metadata.getPackageInfo('test_package');
      expect(info, isNotNull);
      expect(info!.latest, isNotNull);
      expect(info.latest!.version, '1.1.0'); // Should return highest semver
      expect(info.latest!.isRetracted, true);
    });

    test('toJson includes retraction info', () async {
      await metadata.retractPackageVersion(
        'test_package',
        '1.0.0',
        message: 'Critical bug',
      );

      final version = await metadata.getPackageVersion('test_package', '1.0.0');
      final json = version!.toJson('http://example.com/archive.tar.gz');

      expect(json['retracted'], true);
      expect(json['retraction_message'], 'Critical bug');
    });

    test('toJson excludes retraction info for non-retracted versions',
        () async {
      final version = await metadata.getPackageVersion('test_package', '1.1.0');
      final json = version!.toJson('http://example.com/archive.tar.gz');

      expect(json.containsKey('retracted'), false);
      expect(json.containsKey('retraction_message'), false);
    });
  });

  group('Version Retraction Edge Cases', () {
    test('can retract and unretract multiple times', () async {
      // Retract
      await metadata.retractPackageVersion('test_package', '1.0.0',
          message: 'First');
      var version = await metadata.getPackageVersion('test_package', '1.0.0');
      expect(version!.isRetracted, true);
      expect(version.retractionMessage, 'First');

      // Unretract
      await metadata.unretractPackageVersion('test_package', '1.0.0');
      version = await metadata.getPackageVersion('test_package', '1.0.0');
      expect(version!.isRetracted, false);

      // Retract again with different message
      await metadata.retractPackageVersion('test_package', '1.0.0',
          message: 'Second');
      version = await metadata.getPackageVersion('test_package', '1.0.0');
      expect(version!.isRetracted, true);
      expect(version.retractionMessage, 'Second');
    });

    test('empty message string is stored', () async {
      await metadata.retractPackageVersion('test_package', '1.0.0',
          message: '');

      final version = await metadata.getPackageVersion('test_package', '1.0.0');
      expect(version!.retractionMessage, '');
    });

    test('long retraction message is stored', () async {
      final longMessage = 'A' * 1000;
      await metadata.retractPackageVersion('test_package', '1.0.0',
          message: longMessage);

      final version = await metadata.getPackageVersion('test_package', '1.0.0');
      expect(version!.retractionMessage, longMessage);
    });
  });
}
