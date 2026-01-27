import 'package:repub_server/src/upstream.dart';
import 'package:test/test.dart';

void main() {
  group('UpstreamPackageInfo', () {
    test('fromJson parses basic package info', () {
      final json = {
        'name': 'test_package',
        'versions': [],
        'isDiscontinued': false,
      };

      final info = UpstreamPackageInfo.fromJson(json);

      expect(info.name, 'test_package');
      expect(info.versions, isEmpty);
      expect(info.isDiscontinued, isFalse);
      expect(info.replacedBy, isNull);
      expect(info.latest, isNull);
    });

    test('fromJson parses discontinued package with replacement', () {
      final json = {
        'name': 'old_package',
        'versions': [],
        'isDiscontinued': true,
        'replacedBy': 'new_package',
      };

      final info = UpstreamPackageInfo.fromJson(json);

      expect(info.name, 'old_package');
      expect(info.isDiscontinued, isTrue);
      expect(info.replacedBy, 'new_package');
    });

    test('fromJson parses latest version', () {
      final json = {
        'name': 'test_package',
        'versions': [],
        'latest': {
          'version': '1.0.0',
          'archive_url': 'https://pub.dev/archives/test_package-1.0.0.tar.gz',
          'pubspec': {'name': 'test_package', 'version': '1.0.0'},
        },
      };

      final info = UpstreamPackageInfo.fromJson(json);

      expect(info.latest, isNotNull);
      expect(info.latest!.version, '1.0.0');
      expect(info.latest!.packageName, 'test_package');
    });

    test('fromJson parses multiple versions', () {
      final json = {
        'name': 'test_package',
        'versions': [
          {
            'version': '1.0.0',
            'archive_url': 'https://pub.dev/archives/test_package-1.0.0.tar.gz',
            'pubspec': {'name': 'test_package', 'version': '1.0.0'},
          },
          {
            'version': '2.0.0',
            'archive_url': 'https://pub.dev/archives/test_package-2.0.0.tar.gz',
            'pubspec': {'name': 'test_package', 'version': '2.0.0'},
          },
        ],
      };

      final info = UpstreamPackageInfo.fromJson(json);

      expect(info.versions, hasLength(2));
      expect(info.versions[0].version, '1.0.0');
      expect(info.versions[1].version, '2.0.0');
    });

    test('fromJson handles missing fields gracefully', () {
      final json = {
        'name': 'minimal_package',
      };

      final info = UpstreamPackageInfo.fromJson(json);

      expect(info.name, 'minimal_package');
      expect(info.versions, isEmpty);
      expect(info.isDiscontinued, isFalse);
      expect(info.replacedBy, isNull);
      expect(info.latest, isNull);
    });
  });

  group('UpstreamVersionInfo', () {
    test('fromJson parses version info', () {
      final json = {
        'version': '1.2.3',
        'archive_url': 'https://pub.dev/archives/pkg-1.2.3.tar.gz',
        'archive_sha256': 'abc123',
        'pubspec': {
          'name': 'pkg',
          'version': '1.2.3',
          'description': 'Test package',
        },
        'published': '2026-01-15T10:30:00Z',
      };

      final info = UpstreamVersionInfo.fromJson('pkg', json);

      expect(info.packageName, 'pkg');
      expect(info.version, '1.2.3');
      expect(info.archiveUrl, 'https://pub.dev/archives/pkg-1.2.3.tar.gz');
      expect(info.archiveSha256, 'abc123');
      expect(info.pubspec['name'], 'pkg');
      expect(info.pubspec['description'], 'Test package');
      expect(info.published, isNotNull);
      expect(info.published!.year, 2026);
      expect(info.published!.month, 1);
      expect(info.published!.day, 15);
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'version': '1.0.0',
      };

      final info = UpstreamVersionInfo.fromJson('pkg', json);

      expect(info.packageName, 'pkg');
      expect(info.version, '1.0.0');
      expect(info.archiveUrl, '');
      expect(info.archiveSha256, isNull);
      expect(info.pubspec, isEmpty);
      expect(info.published, isNull);
    });

    test('fromJson handles invalid published date', () {
      final json = <String, dynamic>{
        'version': '1.0.0',
        'archive_url': 'https://example.com/archive.tar.gz',
        'pubspec': <String, dynamic>{},
        'published': 'not-a-date',
      };

      final info = UpstreamVersionInfo.fromJson('pkg', json);

      expect(info.published, isNull);
    });

    test('fromJson preserves full pubspec', () {
      final json = {
        'version': '1.0.0',
        'archive_url': 'https://example.com/archive.tar.gz',
        'pubspec': {
          'name': 'my_package',
          'version': '1.0.0',
          'description': 'A comprehensive package',
          'homepage': 'https://example.com',
          'environment': {'sdk': '>=3.0.0 <4.0.0'},
          'dependencies': {'http': '^1.0.0'},
          'dev_dependencies': {'test': '^1.0.0'},
        },
      };

      final info = UpstreamVersionInfo.fromJson('my_package', json);

      expect(info.pubspec['name'], 'my_package');
      expect(info.pubspec['homepage'], 'https://example.com');
      expect(info.pubspec['environment'], {'sdk': '>=3.0.0 <4.0.0'});
      expect(info.pubspec['dependencies'], {'http': '^1.0.0'});
    });
  });

  group('UpstreamClient configuration', () {
    test('initializes with base URL', () {
      final client = UpstreamClient(baseUrl: 'https://pub.dev');
      expect(client.baseUrl, 'https://pub.dev');
      client.dispose();
    });

    test('can be disposed', () {
      final client = UpstreamClient(baseUrl: 'https://pub.dev');
      // Should not throw
      expect(() => client.dispose(), returnsNormally);
    });
  });

  group('JSON parsing edge cases', () {
    test('UpstreamPackageInfo handles null versions list', () {
      final json = {
        'name': 'pkg',
        'versions': null,
      };

      final info = UpstreamPackageInfo.fromJson(json);
      expect(info.versions, isEmpty);
    });

    test('UpstreamVersionInfo with complex pubspec', () {
      final json = {
        'version': '1.0.0',
        'archive_url': 'url',
        'pubspec': {
          'name': 'pkg',
          'executables': {'cli': 'main'},
          'platforms': {'android': null, 'ios': null},
          'funding': ['https://github.com/sponsors/example'],
          'topics': ['utility', 'cli'],
        },
      };

      final info = UpstreamVersionInfo.fromJson('pkg', json);

      expect(info.pubspec['executables'], {'cli': 'main'});
      expect(info.pubspec['topics'], ['utility', 'cli']);
    });
  });
}
