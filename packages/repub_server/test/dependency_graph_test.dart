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

  group('Dependency Graph', () {
    test('getPackageInfo returns pubspec with dependencies', () async {
      // Create a package with dependencies
      await metadata.upsertPackageVersion(
        packageName: 'my_package',
        version: '1.0.0',
        pubspec: {
          'name': 'my_package',
          'version': '1.0.0',
          'dependencies': {
            'http': '^1.0.0',
            'json_annotation': '^4.8.0',
          },
          'dev_dependencies': {
            'test': '^1.24.0',
            'build_runner': '^2.4.0',
          },
          'environment': {
            'sdk': '>=3.0.0 <4.0.0',
          },
        },
        archiveKey: 'packages/my_package-1.0.0.tar.gz',
        archiveSha256: 'abc123',
      );

      final info = await metadata.getPackageInfo('my_package');
      expect(info, isNotNull);
      expect(info!.latest, isNotNull);

      final pubspec = info.latest!.pubspec;
      expect(pubspec['name'], equals('my_package'));
      expect(pubspec['dependencies'], isA<Map>());
      expect((pubspec['dependencies'] as Map)['http'], equals('^1.0.0'));
      expect((pubspec['dependencies'] as Map)['json_annotation'], equals('^4.8.0'));
      expect(pubspec['dev_dependencies'], isA<Map>());
      expect((pubspec['dev_dependencies'] as Map)['test'], equals('^1.24.0'));
      expect(pubspec['environment'], isA<Map>());
      expect((pubspec['environment'] as Map)['sdk'], equals('>=3.0.0 <4.0.0'));
    });

    test('finds reverse dependencies', () async {
      // Create a base package
      await metadata.upsertPackageVersion(
        packageName: 'common_utils',
        version: '1.0.0',
        pubspec: {
          'name': 'common_utils',
          'version': '1.0.0',
          'dependencies': {},
        },
        archiveKey: 'packages/common_utils-1.0.0.tar.gz',
        archiveSha256: 'base123',
      );

      // Create packages that depend on common_utils
      await metadata.upsertPackageVersion(
        packageName: 'app_core',
        version: '2.0.0',
        pubspec: {
          'name': 'app_core',
          'version': '2.0.0',
          'dependencies': {
            'common_utils': '^1.0.0',
          },
        },
        archiveKey: 'packages/app_core-2.0.0.tar.gz',
        archiveSha256: 'core123',
      );

      await metadata.upsertPackageVersion(
        packageName: 'app_ui',
        version: '1.5.0',
        pubspec: {
          'name': 'app_ui',
          'version': '1.5.0',
          'dev_dependencies': {
            'common_utils': '^1.0.0',
          },
        },
        archiveKey: 'packages/app_ui-1.5.0.tar.gz',
        archiveSha256: 'ui123',
      );

      // List all packages and check dependencies manually
      final packages =
          await metadata.listPackagesByType(isUpstreamCache: false);
      expect(packages.packages.length, equals(3));

      // Verify dependencies are correctly stored
      final appCore =
          packages.packages.firstWhere((p) => p.package.name == 'app_core');
      final deps = appCore.latest!.pubspec['dependencies'] as Map?;
      expect(deps, containsPair('common_utils', '^1.0.0'));

      final appUi =
          packages.packages.firstWhere((p) => p.package.name == 'app_ui');
      final devDeps = appUi.latest!.pubspec['dev_dependencies'] as Map?;
      expect(devDeps, containsPair('common_utils', '^1.0.0'));
    });

    test('handles package with no dependencies', () async {
      await metadata.upsertPackageVersion(
        packageName: 'standalone',
        version: '1.0.0',
        pubspec: {
          'name': 'standalone',
          'version': '1.0.0',
        },
        archiveKey: 'packages/standalone-1.0.0.tar.gz',
        archiveSha256: 'standalone123',
      );

      final info = await metadata.getPackageInfo('standalone');
      expect(info, isNotNull);
      expect(info!.latest!.pubspec['dependencies'], isNull);
      expect(info.latest!.pubspec['dev_dependencies'], isNull);
    });

    test('handles package with nested dependency constraints', () async {
      await metadata.upsertPackageVersion(
        packageName: 'complex_deps',
        version: '1.0.0',
        pubspec: {
          'name': 'complex_deps',
          'version': '1.0.0',
          'dependencies': {
            'simple_dep': '^1.0.0',
            'git_dep': {
              'git': {
                'url': 'https://github.com/example/repo',
                'ref': 'main',
              },
            },
            'path_dep': {
              'path': '../local_package',
            },
            'hosted_dep': {
              'hosted': 'https://custom.pub.dev',
              'version': '^2.0.0',
            },
          },
        },
        archiveKey: 'packages/complex_deps-1.0.0.tar.gz',
        archiveSha256: 'complex123',
      );

      final info = await metadata.getPackageInfo('complex_deps');
      expect(info, isNotNull);

      final deps = info!.latest!.pubspec['dependencies'] as Map;
      expect(deps['simple_dep'], equals('^1.0.0'));
      expect(deps['git_dep'], isA<Map>());
      expect((deps['git_dep'] as Map)['git'], isA<Map>());
      expect(deps['path_dep'], isA<Map>());
      expect((deps['path_dep'] as Map)['path'], equals('../local_package'));
    });

    test('dependency data preserved across multiple versions', () async {
      // Version 1.0.0 with one dependency
      await metadata.upsertPackageVersion(
        packageName: 'evolving',
        version: '1.0.0',
        pubspec: {
          'name': 'evolving',
          'version': '1.0.0',
          'dependencies': {
            'dep_a': '^1.0.0',
          },
        },
        archiveKey: 'packages/evolving-1.0.0.tar.gz',
        archiveSha256: 'v1hash',
      );

      // Version 2.0.0 with different dependencies
      await metadata.upsertPackageVersion(
        packageName: 'evolving',
        version: '2.0.0',
        pubspec: {
          'name': 'evolving',
          'version': '2.0.0',
          'dependencies': {
            'dep_a': '^2.0.0',
            'dep_b': '^1.0.0',
          },
        },
        archiveKey: 'packages/evolving-2.0.0.tar.gz',
        archiveSha256: 'v2hash',
      );

      final info = await metadata.getPackageInfo('evolving');
      expect(info, isNotNull);
      expect(info!.versions.length, equals(2));

      // Latest should have both dependencies
      expect(info.latest!.version, equals('2.0.0'));
      final latestDeps = info.latest!.pubspec['dependencies'] as Map;
      expect(latestDeps.length, equals(2));
      expect(latestDeps['dep_a'], equals('^2.0.0'));
      expect(latestDeps['dep_b'], equals('^1.0.0'));

      // Check older version still has correct deps
      final v1 = info.versions.firstWhere((v) => v.version == '1.0.0');
      final v1Deps = v1.pubspec['dependencies'] as Map;
      expect(v1Deps.length, equals(1));
      expect(v1Deps['dep_a'], equals('^1.0.0'));
    });
  });
}
