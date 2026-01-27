import 'package:repub_model/repub_model.dart';
import 'package:repub_server/src/feed.dart';
import 'package:test/test.dart';

void main() {
  group('FeedGenerator', () {
    late FeedGenerator feed;

    setUp(() {
      feed = FeedGenerator(
        baseUrl: 'https://example.com',
        title: 'Test Feed',
        description: 'Test feed description',
      );
    });

    PackageInfo createTestPackage({
      required String name,
      List<PackageVersion>? versions,
      bool isUpstreamCache = false,
    }) {
      return PackageInfo(
        package: Package(
          name: name,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          isUpstreamCache: isUpstreamCache,
        ),
        versions: versions ??
            [
              PackageVersion(
                packageName: name,
                version: '1.0.0',
                pubspec: {
                  'name': name,
                  'version': '1.0.0',
                  'description': 'Test package $name',
                  'environment': {'sdk': '>=3.0.0 <4.0.0'},
                },
                archiveKey: 'archives/$name-1.0.0.tar.gz',
                archiveSha256: 'sha256-placeholder',
                publishedAt: DateTime(2026, 1, 15, 10, 30),
              ),
            ],
      );
    }

    group('generateRss', () {
      test('generates valid RSS 2.0 XML structure', () {
        final packages = [createTestPackage(name: 'test_pkg')];
        final rss = feed.generateRss(packages);

        expect(rss, contains('<?xml version="1.0" encoding="UTF-8"?>'));
        expect(rss, contains('<rss version="2.0"'));
        expect(rss, contains('xmlns:atom="http://www.w3.org/2005/Atom"'));
        expect(rss, contains('<channel>'));
        expect(rss, contains('</channel>'));
        expect(rss, contains('</rss>'));
      });

      test('includes channel metadata', () {
        final packages = [createTestPackage(name: 'test_pkg')];
        final rss = feed.generateRss(packages);

        expect(rss, contains('<title>Test Feed</title>'));
        expect(rss, contains('<link>https://example.com</link>'));
        expect(rss, contains('<description>Test feed description</description>'));
        expect(rss, contains('<lastBuildDate>'));
        expect(rss, contains('atom:link href="https://example.com/feed.rss"'));
      });

      test('generates item for each package version', () {
        final packages = [
          createTestPackage(
            name: 'pkg_a',
            versions: [
              PackageVersion(
                packageName: 'pkg_a',
                version: '1.0.0',
                pubspec: {'name': 'pkg_a', 'description': 'Package A'},
                archiveKey: 'key',
                archiveSha256: 'sha',
                publishedAt: DateTime(2026, 1, 10),
              ),
              PackageVersion(
                packageName: 'pkg_a',
                version: '2.0.0',
                pubspec: {'name': 'pkg_a', 'description': 'Package A'},
                archiveKey: 'key',
                archiveSha256: 'sha',
                publishedAt: DateTime(2026, 1, 15),
              ),
            ],
          ),
        ];
        final rss = feed.generateRss(packages);

        expect(rss, contains('<item>'));
        expect(rss, contains('<title>pkg_a 1.0.0</title>'));
        expect(rss, contains('<title>pkg_a 2.0.0</title>'));
        expect(rss, contains('<link>https://example.com/packages/pkg_a</link>'));
        expect(rss, contains('<guid isPermaLink="false">pkg_a-1.0.0</guid>'));
        expect(rss, contains('<guid isPermaLink="false">pkg_a-2.0.0</guid>'));
      });

      test('excludes cached packages from global feed', () {
        final packages = [
          createTestPackage(name: 'local_pkg'),
          createTestPackage(name: 'cached_pkg', isUpstreamCache: true),
        ];
        final rss = feed.generateRss(packages);

        expect(rss, contains('local_pkg'));
        expect(rss, isNot(contains('cached_pkg')));
      });

      test('limits items to specified count', () {
        final versions = List.generate(
          30,
          (i) => PackageVersion(
            packageName: 'pkg',
            version: '1.0.$i',
            pubspec: {'name': 'pkg'},
            archiveKey: 'key',
            archiveSha256: 'sha',
            publishedAt: DateTime(2026, 1, i + 1),
          ),
        );
        final packages = [createTestPackage(name: 'pkg', versions: versions)];
        final rss = feed.generateRss(packages, limit: 10);

        // Count item tags
        final itemCount = RegExp(r'<item>').allMatches(rss).length;
        expect(itemCount, equals(10));
      });

      test('sorts items by publish date descending', () {
        final packages = [
          createTestPackage(
            name: 'pkg',
            versions: [
              PackageVersion(
                packageName: 'pkg',
                version: '1.0.0',
                pubspec: {'name': 'pkg'},
                archiveKey: 'key',
                archiveSha256: 'sha',
                publishedAt: DateTime(2026, 1, 1), // Oldest
              ),
              PackageVersion(
                packageName: 'pkg',
                version: '3.0.0',
                pubspec: {'name': 'pkg'},
                archiveKey: 'key',
                archiveSha256: 'sha',
                publishedAt: DateTime(2026, 1, 15), // Newest
              ),
              PackageVersion(
                packageName: 'pkg',
                version: '2.0.0',
                pubspec: {'name': 'pkg'},
                archiveKey: 'key',
                archiveSha256: 'sha',
                publishedAt: DateTime(2026, 1, 10), // Middle
              ),
            ],
          ),
        ];
        final rss = feed.generateRss(packages);

        // 3.0.0 should appear before 2.0.0 which should appear before 1.0.0
        final idx30 = rss.indexOf('3.0.0');
        final idx20 = rss.indexOf('2.0.0');
        final idx10 = rss.indexOf('1.0.0');

        expect(idx30, lessThan(idx20));
        expect(idx20, lessThan(idx10));
      });

      test('escapes XML special characters', () {
        final packages = [
          PackageInfo(
            package: Package(
              name: 'pkg',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
            versions: [
              PackageVersion(
                packageName: 'pkg',
                version: '1.0.0',
                pubspec: {
                  'name': 'pkg',
                  'description': 'Contains <html> & "special" characters',
                },
                archiveKey: 'key',
                archiveSha256: 'sha',
                publishedAt: DateTime(2026, 1, 1),
              ),
            ],
          ),
        ];
        final rss = feed.generateRss(packages);

        expect(rss, contains('&lt;html&gt;'));
        expect(rss, contains('&amp;'));
        expect(rss, contains('&quot;special&quot;'));
      });

      test('handles empty package list', () {
        final rss = feed.generateRss([]);

        expect(rss, contains('<channel>'));
        expect(rss, isNot(contains('<item>')));
      });
    });

    group('generateAtom', () {
      test('generates valid Atom 1.0 XML structure', () {
        final packages = [createTestPackage(name: 'test_pkg')];
        final atom = feed.generateAtom(packages);

        expect(atom, contains('<?xml version="1.0" encoding="UTF-8"?>'));
        expect(atom, contains('<feed xmlns="http://www.w3.org/2005/Atom">'));
        expect(atom, contains('</feed>'));
      });

      test('includes feed metadata', () {
        final packages = [createTestPackage(name: 'test_pkg')];
        final atom = feed.generateAtom(packages);

        expect(atom, contains('<title>Test Feed</title>'));
        expect(atom, contains('<subtitle>Test feed description</subtitle>'));
        expect(atom, contains('<link href="https://example.com" rel="alternate"/>'));
        expect(atom, contains('<link href="https://example.com/feed.atom" rel="self"/>'));
        expect(atom, contains('<id>https://example.com/</id>'));
        expect(atom, contains('<updated>'));
      });

      test('generates entry for each package version', () {
        final packages = [createTestPackage(name: 'test_pkg')];
        final atom = feed.generateAtom(packages);

        expect(atom, contains('<entry>'));
        expect(atom, contains('<title>test_pkg 1.0.0</title>'));
        expect(atom, contains('<link href="https://example.com/packages/test_pkg"/>'));
        expect(atom, contains('<id>https://example.com/packages/test_pkg/versions/1.0.0</id>'));
        expect(atom, contains('<published>'));
        expect(atom, contains('<summary type="text">'));
        expect(atom, contains('<content type="html">'));
      });

      test('includes package description in content', () {
        final packages = [createTestPackage(name: 'test_pkg')];
        final atom = feed.generateAtom(packages);

        expect(atom, contains('Test package test_pkg'));
      });
    });

    group('generatePackageRss', () {
      test('generates feed for specific package', () {
        final pkg = createTestPackage(name: 'my_package');
        final rss = feed.generatePackageRss(pkg);

        expect(rss, contains('<title>my_package - Package Updates</title>'));
        expect(rss, contains('<link>https://example.com/packages/my_package</link>'));
        expect(rss, contains('atom:link href="https://example.com/packages/my_package/feed.rss"'));
      });

      test('includes all package versions', () {
        final pkg = createTestPackage(
          name: 'pkg',
          versions: [
            PackageVersion(
              packageName: 'pkg',
              version: '1.0.0',
              pubspec: {'name': 'pkg'},
              archiveKey: 'key',
              archiveSha256: 'sha',
              publishedAt: DateTime(2026, 1, 1),
            ),
            PackageVersion(
              packageName: 'pkg',
              version: '1.1.0',
              pubspec: {'name': 'pkg'},
              archiveKey: 'key',
              archiveSha256: 'sha',
              publishedAt: DateTime(2026, 1, 10),
            ),
          ],
        );
        final rss = feed.generatePackageRss(pkg);

        expect(rss, contains('pkg 1.0.0'));
        expect(rss, contains('pkg 1.1.0'));
      });

      test('uses package description from latest version', () {
        final pkg = PackageInfo(
          package: Package(
            name: 'pkg',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
          versions: [
            PackageVersion(
              packageName: 'pkg',
              version: '2.0.0',
              pubspec: {
                'name': 'pkg',
                'description': 'Latest description',
              },
              archiveKey: 'key',
              archiveSha256: 'sha',
              publishedAt: DateTime(2026, 1, 10),
            ),
          ],
        );
        final rss = feed.generatePackageRss(pkg);

        expect(rss, contains('Latest description'));
      });
    });

    group('generatePackageAtom', () {
      test('generates Atom feed for specific package', () {
        final pkg = createTestPackage(name: 'my_package');
        final atom = feed.generatePackageAtom(pkg);

        expect(atom, contains('<title>my_package - Package Updates</title>'));
        expect(atom, contains('<link href="https://example.com/packages/my_package" rel="alternate"/>'));
        expect(atom, contains('<link href="https://example.com/packages/my_package/feed.atom" rel="self"/>'));
        expect(atom, contains('<id>https://example.com/packages/my_package</id>'));
      });
    });

    group('date formatting', () {
      test('RSS date format is RFC 822', () {
        final packages = [
          PackageInfo(
            package: Package(
              name: 'pkg',
              createdAt: DateTime(2026, 1, 15),
              updatedAt: DateTime(2026, 1, 15),
            ),
            versions: [
              PackageVersion(
                packageName: 'pkg',
                version: '1.0.0',
                pubspec: {'name': 'pkg'},
                archiveKey: 'key',
                archiveSha256: 'sha',
                publishedAt: DateTime.utc(2026, 3, 15, 14, 30, 45),
              ),
            ],
          ),
        ];
        final rss = feed.generateRss(packages);

        // RFC 822 format: Sun, 15 Mar 2026 14:30:45 +0000
        expect(rss, contains('Sun, 15 Mar 2026 14:30:45 +0000'));
      });

      test('Atom date format is ISO 8601', () {
        final packages = [
          PackageInfo(
            package: Package(
              name: 'pkg',
              createdAt: DateTime(2026, 1, 15),
              updatedAt: DateTime(2026, 1, 15),
            ),
            versions: [
              PackageVersion(
                packageName: 'pkg',
                version: '1.0.0',
                pubspec: {'name': 'pkg'},
                archiveKey: 'key',
                archiveSha256: 'sha',
                publishedAt: DateTime.utc(2026, 3, 15, 14, 30, 45),
              ),
            ],
          ),
        ];
        final atom = feed.generateAtom(packages);

        // ISO 8601 format
        expect(atom, contains('2026-03-15T14:30:45.000Z'));
      });
    });
  });
}
