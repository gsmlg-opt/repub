import 'package:repub_model/repub_model.dart';
import 'package:test/test.dart';

void main() {
  group('Package', () {
    test('canPublish returns false for upstream cache packages', () {
      final pkg = Package(
        name: 'cached_pkg',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isUpstreamCache: true,
      );

      expect(pkg.canPublish('user123'), isFalse);
      expect(pkg.canPublish(null), isFalse);
    });

    test('canPublish returns true for packages without owner', () {
      final pkg = Package(
        name: 'no_owner_pkg',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        ownerId: null,
      );

      expect(pkg.canPublish('any_user'), isTrue);
      expect(pkg.canPublish(null), isTrue);
    });

    test('canPublish returns true only for owner', () {
      final pkg = Package(
        name: 'owned_pkg',
        ownerId: 'user123',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(pkg.canPublish('user123'), isTrue);
      expect(pkg.canPublish('other_user'), isFalse);
      expect(pkg.canPublish(null), isFalse);
    });

    test('toJson includes correct fields', () {
      final pkg = Package(
        name: 'test_pkg',
        ownerId: 'owner1',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        isDiscontinued: true,
        replacedBy: 'new_pkg',
      );

      final json = pkg.toJson();

      expect(json['name'], 'test_pkg');
      expect(json['ownerId'], 'owner1');
      expect(json['isDiscontinued'], true);
      expect(json['replacedBy'], 'new_pkg');
    });

    test('toJson omits optional fields when not set', () {
      final pkg = Package(
        name: 'minimal_pkg',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = pkg.toJson();

      expect(json['name'], 'minimal_pkg');
      expect(json.containsKey('ownerId'), isFalse);
      expect(json.containsKey('isDiscontinued'), isFalse);
      expect(json.containsKey('replacedBy'), isFalse);
    });
  });

  group('PackageVersion', () {
    final testVersion = PackageVersion(
      packageName: 'test_pkg',
      version: '1.0.0',
      pubspec: {'name': 'test_pkg', 'version': '1.0.0'},
      archiveKey: 'test_pkg/1.0.0.tar.gz',
      archiveSha256: 'abc123sha256',
      publishedAt: DateTime(2024, 1, 1),
    );

    test('copyWith creates copy with updated fields', () {
      final retracted = testVersion.copyWith(
        isRetracted: true,
        retractedAt: DateTime(2024, 2, 1),
        retractionMessage: 'Security issue',
      );

      expect(retracted.packageName, 'test_pkg');
      expect(retracted.version, '1.0.0');
      expect(retracted.isRetracted, isTrue);
      expect(retracted.retractedAt, DateTime(2024, 2, 1));
      expect(retracted.retractionMessage, 'Security issue');
    });

    test('copyWith preserves original values when not specified', () {
      final copy = testVersion.copyWith(isRetracted: true);

      expect(copy.archiveSha256, testVersion.archiveSha256);
      expect(copy.publishedAt, testVersion.publishedAt);
    });

    test('toJson includes retraction info when retracted', () {
      final retracted = PackageVersion(
        packageName: 'pkg',
        version: '1.0.0',
        pubspec: {'name': 'pkg'},
        archiveKey: 'key',
        archiveSha256: 'sha',
        publishedAt: DateTime.now(),
        isRetracted: true,
        retractionMessage: 'Security fix',
      );

      final json = retracted.toJson('http://example.com/pkg/1.0.0.tar.gz');

      expect(json['retracted'], isTrue);
    });
  });

  group('PackageInfo', () {
    test('latest returns highest non-retracted version', () {
      final versions = [
        PackageVersion(
          packageName: 'pkg',
          version: '1.0.0',
          pubspec: {'name': 'pkg', 'version': '1.0.0'},
          archiveKey: 'k1',
          archiveSha256: 's1',
          publishedAt: DateTime(2024, 1, 1),
        ),
        PackageVersion(
          packageName: 'pkg',
          version: '2.0.0',
          pubspec: {'name': 'pkg', 'version': '2.0.0'},
          archiveKey: 'k2',
          archiveSha256: 's2',
          publishedAt: DateTime(2024, 2, 1),
        ),
        PackageVersion(
          packageName: 'pkg',
          version: '3.0.0',
          pubspec: {'name': 'pkg', 'version': '3.0.0'},
          archiveKey: 'k3',
          archiveSha256: 's3',
          publishedAt: DateTime(2024, 3, 1),
          isRetracted: true,
        ),
      ];

      final info = PackageInfo(
        package: Package(
          name: 'pkg',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        versions: versions,
      );

      expect(info.latest?.version, '2.0.0');
    });

    test('latest returns highest version when all retracted', () {
      final versions = [
        PackageVersion(
          packageName: 'pkg',
          version: '1.0.0',
          pubspec: {'name': 'pkg'},
          archiveKey: 'k1',
          archiveSha256: 's1',
          publishedAt: DateTime(2024, 1, 1),
          isRetracted: true,
        ),
        PackageVersion(
          packageName: 'pkg',
          version: '2.0.0',
          pubspec: {'name': 'pkg'},
          archiveKey: 'k2',
          archiveSha256: 's2',
          publishedAt: DateTime(2024, 2, 1),
          isRetracted: true,
        ),
      ];

      final info = PackageInfo(
        package: Package(
          name: 'pkg',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        versions: versions,
      );

      expect(info.latest?.version, '2.0.0');
    });

    test('latest returns null for empty versions', () {
      final info = PackageInfo(
        package: Package(
          name: 'pkg',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        versions: [],
      );

      expect(info.latest, isNull);
    });
  });

  group('PackageListResult', () {
    test('totalPages calculates correctly', () {
      final result = PackageListResult(
        packages: [],
        total: 25,
        page: 1,
        limit: 10,
      );

      expect(result.totalPages, 3);
    });

    test('totalPages handles exact division', () {
      final result = PackageListResult(
        packages: [],
        total: 20,
        page: 1,
        limit: 10,
      );

      expect(result.totalPages, 2);
    });

    test('totalPages handles zero total', () {
      final result = PackageListResult(
        packages: [],
        total: 0,
        page: 1,
        limit: 10,
      );

      expect(result.totalPages, 0);
    });
  });

  group('AuthToken', () {
    test('isExpired returns true for past date', () {
      final token = AuthToken(
        tokenHash: 'hash',
        userId: 'user1',
        label: 'test',
        scopes: ['read:all'],
        createdAt: DateTime(2020, 1, 1),
        expiresAt: DateTime(2020, 2, 1),
      );

      expect(token.isExpired, isTrue);
    });

    test('isExpired returns false for future date', () {
      final token = AuthToken(
        tokenHash: 'hash',
        userId: 'user1',
        label: 'test',
        scopes: ['read:all'],
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );

      expect(token.isExpired, isFalse);
    });

    test('isExpired returns false when no expiry set', () {
      final token = AuthToken(
        tokenHash: 'hash',
        userId: 'user1',
        label: 'test',
        scopes: ['read:all'],
        createdAt: DateTime.now(),
        expiresAt: null,
      );

      expect(token.isExpired, isFalse);
    });

    test('hasScope checks for specific scope', () {
      final token = AuthToken(
        tokenHash: 'hash',
        userId: 'user1',
        label: 'test',
        scopes: ['read:all', 'publish:all'],
        createdAt: DateTime.now(),
      );

      expect(token.hasScope('read:all'), isTrue);
      expect(token.hasScope('publish:all'), isTrue);
      expect(token.hasScope('admin'), isFalse);
    });

    test('isAdmin returns true for admin scope', () {
      final adminToken = AuthToken(
        tokenHash: 'hash',
        userId: 'user1',
        label: 'test',
        scopes: ['admin'],
        createdAt: DateTime.now(),
      );

      expect(adminToken.isAdmin, isTrue);
    });

    test('canPublishAll returns true for admin or publish:all', () {
      final adminToken = AuthToken(
        tokenHash: 'hash',
        userId: 'user1',
        label: 'admin_token',
        scopes: ['admin'],
        createdAt: DateTime.now(),
      );

      final publishAllToken = AuthToken(
        tokenHash: 'hash',
        userId: 'user1',
        label: 'publish_token',
        scopes: ['publish:all'],
        createdAt: DateTime.now(),
      );

      final readOnlyToken = AuthToken(
        tokenHash: 'hash',
        userId: 'user1',
        label: 'read_token',
        scopes: ['read:all'],
        createdAt: DateTime.now(),
      );

      expect(adminToken.canPublishAll, isTrue);
      expect(publishAllToken.canPublishAll, isTrue);
      expect(readOnlyToken.canPublishAll, isFalse);
    });

    test('canPublish checks package-specific scope', () {
      final token = AuthToken(
        tokenHash: 'hash',
        userId: 'user1',
        label: 'test',
        scopes: ['publish:pkg:my_package'],
        createdAt: DateTime.now(),
      );

      expect(token.canPublish('my_package'), isTrue);
      expect(token.canPublish('other_package'), isFalse);
    });
  });

  group('UploadSession', () {
    test('isExpired returns true for past date', () {
      final session = UploadSession(
        id: '1',
        createdAt: DateTime(2020, 1, 1),
        expiresAt: DateTime(2020, 2, 1),
      );

      expect(session.isExpired, isTrue);
    });

    test('isExpired returns false for future date', () {
      final session = UploadSession(
        id: '1',
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(session.isExpired, isFalse);
    });
  });

  group('User', () {
    test('creates with correct fields', () {
      final user = User(
        id: 'user123',
        email: 'test@example.com',
        passwordHash: 'hash123',
        name: 'Test User',
        isActive: true,
        createdAt: DateTime(2024, 1, 1),
        lastLoginAt: DateTime(2024, 6, 1),
      );

      expect(user.id, 'user123');
      expect(user.email, 'test@example.com');
      expect(user.name, 'Test User');
      expect(user.isActive, isTrue);
    });

    test('isActive defaults to true', () {
      final user = User(
        id: 'user1',
        email: 'user@example.com',
        passwordHash: 'hash',
        createdAt: DateTime.now(),
      );

      expect(user.isActive, isTrue);
    });
  });

  group('AdminUser', () {
    test('creates with correct fields', () {
      final admin = AdminUser(
        id: 'admin1',
        username: 'superadmin',
        passwordHash: 'hash',
        name: 'Super Admin',
        isActive: true,
        mustChangePassword: false,
        createdAt: DateTime(2024, 1, 1),
      );

      expect(admin.id, 'admin1');
      expect(admin.username, 'superadmin');
      expect(admin.name, 'Super Admin');
      expect(admin.isActive, isTrue);
      expect(admin.mustChangePassword, isFalse);
    });

    test('mustChangePassword defaults to false', () {
      final admin = AdminUser(
        id: 'admin1',
        username: 'admin',
        passwordHash: 'hash',
        name: 'Admin',
        isActive: true,
        createdAt: DateTime.now(),
      );

      expect(admin.mustChangePassword, isFalse);
    });
  });

  group('SiteConfig', () {
    test('creates with correct fields', () {
      final config = SiteConfig(
        name: 'allow_registration',
        valueType: ConfigValueType.boolean,
        value: 'true',
        description: 'Allow new user registration',
      );

      expect(config.name, 'allow_registration');
      expect(config.valueType, ConfigValueType.boolean);
      expect(config.value, 'true');
    });

    test('SiteConfigDefaults contains expected defaults', () {
      expect(
        SiteConfigDefaults.all.any((c) => c.name == 'allow_registration'),
        isTrue,
      );
      expect(
        SiteConfigDefaults.all.any((c) => c.name == 'smtp_host'),
        isTrue,
      );
    });
  });

  group('Webhook', () {
    final testWebhook = Webhook(
      id: 'wh1',
      url: 'https://example.com/webhook',
      secret: 'secret123',
      events: ['package.published', 'user.registered'],
      isActive: true,
      failureCount: 0,
      createdAt: DateTime(2024, 1, 1),
    );

    test('shouldTrigger returns true for matching event', () {
      expect(testWebhook.shouldTrigger('package.published'), isTrue);
      expect(testWebhook.shouldTrigger('user.registered'), isTrue);
    });

    test('shouldTrigger returns false for non-matching event', () {
      expect(testWebhook.shouldTrigger('package.deleted'), isFalse);
    });

    test('shouldTrigger returns false when inactive', () {
      final inactive = Webhook(
        id: 'wh2',
        url: 'https://example.com/webhook',
        events: ['*'],
        isActive: false,
        failureCount: 0,
        createdAt: DateTime.now(),
      );

      expect(inactive.shouldTrigger('package.published'), isFalse);
    });

    test('shouldTrigger returns true for wildcard', () {
      final wildcard = Webhook(
        id: 'wh3',
        url: 'https://example.com/webhook',
        events: ['*'],
        isActive: true,
        failureCount: 0,
        createdAt: DateTime.now(),
      );

      expect(wildcard.shouldTrigger('package.published'), isTrue);
      expect(wildcard.shouldTrigger('any.event'), isTrue);
    });

    test('toJson excludes secret', () {
      final json = testWebhook.toJson();

      expect(json['id'], 'wh1');
      expect(json['url'], 'https://example.com/webhook');
      expect(json.containsKey('secret'), isFalse);
    });

    test('copyWith creates modified copy', () {
      final modified = testWebhook.copyWith(
        isActive: false,
        failureCount: 5,
      );

      expect(modified.id, 'wh1');
      expect(modified.url, 'https://example.com/webhook');
      expect(modified.isActive, isFalse);
      expect(modified.failureCount, 5);
    });
  });

  group('Config', () {
    test('databaseType detects sqlite from sqlite URL', () {
      final config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite:./data/repub.db',
        requireDownloadAuth: false,
        requirePublishAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: true,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      expect(config.databaseType, DatabaseType.sqlite);
    });

    test('databaseType detects postgresql', () {
      final config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'postgres://user:pass@localhost:5432/db',
        requireDownloadAuth: false,
        requirePublishAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: true,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      expect(config.databaseType, DatabaseType.postgresql);
    });

    test('sqlitePath extracts path from sqlite URL', () {
      final config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite:./data/repub.db',
        requireDownloadAuth: false,
        requirePublishAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: true,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      expect(config.sqlitePath, './data/repub.db');
    });

    test('sqlitePath handles plain path', () {
      final config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: './data/repub.db',
        requireDownloadAuth: false,
        requirePublishAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: true,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      expect(config.sqlitePath, './data/repub.db');
    });

    test('useLocalStorage returns true when storagePath set', () {
      final config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite:./db',
        storagePath: './storage',
        requireDownloadAuth: false,
        requirePublishAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: true,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      expect(config.useLocalStorage, isTrue);
    });
  });

  group('ActivityLog', () {
    test('creates with correct fields', () {
      final log = ActivityLog(
        id: 'log1',
        timestamp: DateTime(2024, 1, 1),
        activityType: 'package_published',
        actorType: 'user',
        actorId: 'user123',
        actorEmail: 'user@example.com',
        targetType: 'package',
        targetId: 'my_package',
        metadata: {'version': '1.0.0'},
      );

      expect(log.activityType, 'package_published');
      expect(log.actorType, 'user');
      expect(log.targetType, 'package');
      expect(log.metadata?['version'], '1.0.0');
    });
  });
}
