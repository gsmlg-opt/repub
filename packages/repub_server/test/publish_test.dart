import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:repub_server/src/publish.dart';
import 'package:test/test.dart';

void main() {
  group('validateTarball', () {
    Uint8List createTarball(String pubspecYaml) {
      final archive = Archive();
      archive.addFile(ArchiveFile(
        'pubspec.yaml',
        pubspecYaml.length,
        utf8.encode(pubspecYaml),
      ));

      final tarBytes = TarEncoder().encode(archive);
      final gzipBytes = GZipEncoder().encode(tarBytes);
      return Uint8List.fromList(gzipBytes);
    }

    test('validates valid tarball successfully', () async {
      final tarball = createTarball('''
name: test_package
version: 1.0.0
''');
      final result = await validateTarball(tarball);

      expect(result, isA<PublishSuccess>());
      final success = result as PublishSuccess;
      expect(success.packageName, 'test_package');
      expect(success.version, '1.0.0');
      expect(success.sha256Hash, isNotEmpty);
      expect(success.tarballBytes, equals(tarball));
    });

    test('extracts pubspec fields correctly', () async {
      final tarball = createTarball('''
name: my_package
version: 2.0.0
description: A test package
homepage: https://example.com
''');
      final result = await validateTarball(tarball);

      expect(result, isA<PublishSuccess>());
      final success = result as PublishSuccess;
      expect(success.pubspec['name'], 'my_package');
      expect(success.pubspec['version'], '2.0.0');
      expect(success.pubspec['description'], 'A test package');
      expect(success.pubspec['homepage'], 'https://example.com');
    });

    group('validates package name', () {
      test('accepts valid lowercase names', () async {
        final tarball = createTarball('''
name: my_package
version: 1.0.0
''');
        final result = await validateTarball(tarball);
        expect(result, isA<PublishSuccess>());
      });

      test('accepts names with underscores', () async {
        final tarball = createTarball('''
name: my_great_package
version: 1.0.0
''');
        final result = await validateTarball(tarball);
        expect(result, isA<PublishSuccess>());
      });

      test('accepts names with numbers', () async {
        final tarball = createTarball('''
name: package123
version: 1.0.0
''');
        final result = await validateTarball(tarball);
        expect(result, isA<PublishSuccess>());
      });

      test('rejects names starting with number', () async {
        final tarball = createTarball('''
name: 123package
version: 1.0.0
''');
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
        expect((result as PublishError).message, contains('Invalid package name'));
      });

      test('rejects names with uppercase', () async {
        final tarball = createTarball('''
name: MyPackage
version: 1.0.0
''');
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
        expect((result as PublishError).message, contains('Invalid package name'));
      });

      test('rejects names with hyphens', () async {
        final tarball = createTarball('''
name: my-package
version: 1.0.0
''');
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
        expect((result as PublishError).message, contains('Invalid package name'));
      });

      test('rejects names starting with underscore', () async {
        final tarball = createTarball('''
name: _private
version: 1.0.0
''');
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
        expect((result as PublishError).message, contains('Invalid package name'));
      });
    });

    group('validates version', () {
      test('accepts standard semver', () async {
        final tarball = createTarball('''
name: test_pkg
version: 1.2.3
''');
        final result = await validateTarball(tarball);
        expect(result, isA<PublishSuccess>());
      });

      test('accepts version with prerelease', () async {
        final tarball = createTarball('''
name: test_pkg
version: 1.0.0-beta.1
''');
        final result = await validateTarball(tarball);
        expect(result, isA<PublishSuccess>());
      });

      test('accepts version with build metadata', () async {
        final tarball = createTarball('''
name: test_pkg
version: 1.0.0+build.123
''');
        final result = await validateTarball(tarball);
        expect(result, isA<PublishSuccess>());
      });

      test('accepts version with prerelease and build', () async {
        final tarball = createTarball('''
name: test_pkg
version: 1.0.0-alpha.1+build.456
''');
        final result = await validateTarball(tarball);
        expect(result, isA<PublishSuccess>());
      });

      test('rejects invalid version format', () async {
        final tarball = createTarball('''
name: test_pkg
version: invalid
''');
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
        expect((result as PublishError).message, contains('Invalid version'));
      });
    });

    group('handles missing fields', () {
      test('rejects tarball without pubspec.yaml', () async {
        // Create archive without pubspec
        final archive = Archive();
        archive.addFile(ArchiveFile(
          'README.md',
          10,
          utf8.encode('# Test\n'),
        ));

        final tarBytes = TarEncoder().encode(archive);
        final gzipBytes = GZipEncoder().encode(tarBytes);
        final tarball = Uint8List.fromList(gzipBytes);

        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
        expect((result as PublishError).message, contains('No pubspec.yaml'));
      });

      test('rejects pubspec without name', () async {
        final tarball = createTarball('''
version: 1.0.0
description: A package without a name
''');
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
        expect((result as PublishError).message, contains('name'));
      });

      test('rejects pubspec without version', () async {
        final tarball = createTarball('''
name: test_pkg
description: A package without a version
''');
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
        expect((result as PublishError).message, contains('version'));
      });
    });

    group('handles invalid archives', () {
      test('rejects non-gzip data', () async {
        final tarball = Uint8List.fromList([1, 2, 3, 4, 5]);
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
      });

      test('rejects invalid yaml', () async {
        final tarball = createTarball('{ invalid yaml [');
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
      });

      test('rejects pubspec that is not a map', () async {
        final tarball = createTarball('''
- item1
- item2
''');
        final result = await validateTarball(tarball);

        expect(result, isA<PublishError>());
        expect((result as PublishError).message, contains('not a map'));
      });
    });

    group('handles nested pubspec', () {
      test('finds pubspec in subdirectory', () async {
        final pubspec = 'name: nested_pkg\nversion: 1.0.0\n';
        final archive = Archive();
        archive.addFile(ArchiveFile(
          'package/pubspec.yaml',
          pubspec.length,
          utf8.encode(pubspec),
        ));

        final tarBytes = TarEncoder().encode(archive);
        final gzipBytes = GZipEncoder().encode(tarBytes);
        final tarball = Uint8List.fromList(gzipBytes);

        final result = await validateTarball(tarball);

        expect(result, isA<PublishSuccess>());
        expect((result as PublishSuccess).packageName, 'nested_pkg');
      });

      test('prefers root pubspec over nested', () async {
        final rootPubspec = 'name: root_pkg\nversion: 1.0.0\n';
        final nestedPubspec = 'name: nested_pkg\nversion: 2.0.0\n';
        final archive = Archive();
        archive.addFile(ArchiveFile(
          'pubspec.yaml',
          rootPubspec.length,
          utf8.encode(rootPubspec),
        ));
        archive.addFile(ArchiveFile(
          'subdir/pubspec.yaml',
          nestedPubspec.length,
          utf8.encode(nestedPubspec),
        ));

        final tarBytes = TarEncoder().encode(archive);
        final gzipBytes = GZipEncoder().encode(tarBytes);
        final tarball = Uint8List.fromList(gzipBytes);

        final result = await validateTarball(tarball);

        expect(result, isA<PublishSuccess>());
        expect((result as PublishSuccess).packageName, 'root_pkg');
      });
    });

    test('calculates sha256 hash correctly', () async {
      final tarball = createTarball('''
name: test_pkg
version: 1.0.0
''');
      final result = await validateTarball(tarball);

      expect(result, isA<PublishSuccess>());
      final success = result as PublishSuccess;

      // Hash should be 64 hex characters
      expect(success.sha256Hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(success.sha256Hash), isTrue);
    });
  });

  group('PublishSuccess', () {
    test('stores all fields', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final success = PublishSuccess(
        packageName: 'test',
        version: '1.0.0',
        pubspec: {'name': 'test'},
        sha256Hash: 'abc123',
        tarballBytes: bytes,
      );

      expect(success.packageName, 'test');
      expect(success.version, '1.0.0');
      expect(success.pubspec, {'name': 'test'});
      expect(success.sha256Hash, 'abc123');
      expect(success.tarballBytes, bytes);
    });
  });

  group('PublishError', () {
    test('stores message', () {
      final error = PublishError('Something went wrong');
      expect(error.message, 'Something went wrong');
    });
  });
}
