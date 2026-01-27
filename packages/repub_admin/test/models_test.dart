import 'package:flutter_test/flutter_test.dart';

import 'package:repub_admin/models/dashboard_stats.dart';
import 'package:repub_admin/models/package_info.dart';
import 'package:repub_admin/models/user_info.dart';
import 'package:repub_admin/models/admin_user_info.dart';
import 'package:repub_admin/models/site_config.dart';

void main() {
  group('DashboardStats', () {
    test('fromJson parses correctly', () {
      final json = {
        'total_packages': 10,
        'total_users': 5,
        'total_downloads': 100,
        'active_tokens': 3,
        'recent_activity': <Map<String, dynamic>>[],
        'top_packages': <Map<String, dynamic>>[],
      };

      final stats = DashboardStats.fromJson(json);

      expect(stats.totalPackages, 10);
      expect(stats.totalUsers, 5);
      expect(stats.totalDownloads, 100);
      expect(stats.activeTokens, 3);
      expect(stats.recentActivity, isEmpty);
      expect(stats.topPackages, isEmpty);
    });

    test('fromJson handles missing values with defaults', () {
      final json = <String, dynamic>{};

      final stats = DashboardStats.fromJson(json);

      expect(stats.totalPackages, 0);
      expect(stats.totalUsers, 0);
      expect(stats.totalDownloads, 0);
      expect(stats.activeTokens, 0);
    });

    test('toJson roundtrips correctly', () {
      final original = const DashboardStats(
        totalPackages: 10,
        totalUsers: 5,
        totalDownloads: 100,
        activeTokens: 3,
        recentActivity: [],
        topPackages: [],
      );

      final json = original.toJson();
      final restored = DashboardStats.fromJson(json);

      expect(restored, original);
    });
  });

  group('PackageInfo', () {
    test('fromJson parses correctly', () {
      final json = {
        'name': 'test_package',
        'description': 'A test package',
        'latest_version': '1.0.0',
        'created_at': '2024-01-01T00:00:00.000Z',
        'updated_at': '2024-01-02T00:00:00.000Z',
        'download_count': 50,
        'is_discontinued': false,
        'versions': ['1.0.0', '0.9.0'],
        'uploader_email': 'test@example.com',
      };

      final pkg = PackageInfo.fromJson(json);

      expect(pkg.name, 'test_package');
      expect(pkg.description, 'A test package');
      expect(pkg.latestVersion, '1.0.0');
      expect(pkg.downloadCount, 50);
      expect(pkg.isDiscontinued, false);
      expect(pkg.versions, ['1.0.0', '0.9.0']);
      expect(pkg.uploaderEmail, 'test@example.com');
    });

    test('toJson roundtrips correctly', () {
      final original = PackageInfo(
        name: 'my_package',
        description: 'Description',
        latestVersion: '2.0.0',
        createdAt: DateTime.utc(2024, 1, 1),
        downloadCount: 100,
        isDiscontinued: false,
        versions: ['2.0.0', '1.0.0'],
      );

      final json = original.toJson();
      final restored = PackageInfo.fromJson(json);

      expect(restored.name, original.name);
      expect(restored.latestVersion, original.latestVersion);
      expect(restored.downloadCount, original.downloadCount);
    });
  });

  group('UserInfo', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'user-123',
        'email': 'user@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
        'is_active': true,
        'token_count': 3,
        'last_login_at': '2024-01-15T10:30:00.000Z',
      };

      final user = UserInfo.fromJson(json);

      expect(user.id, 'user-123');
      expect(user.email, 'user@example.com');
      expect(user.isActive, true);
      expect(user.tokenCount, 3);
      expect(user.lastLoginAt, isNotNull);
    });

    test('handles null optional fields', () {
      final json = {
        'id': 'user-123',
        'email': 'user@example.com',
        'created_at': '2024-01-01T00:00:00.000Z',
      };

      final user = UserInfo.fromJson(json);

      expect(user.isActive, true);
      expect(user.tokenCount, 0);
      expect(user.lastLoginAt, isNull);
    });
  });

  group('AdminUserInfo', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'admin-123',
        'username': 'admin',
        'created_at': '2024-01-01T00:00:00.000Z',
        'last_login_at': '2024-01-15T10:30:00.000Z',
        'login_count': 42,
      };

      final admin = AdminUserInfo.fromJson(json);

      expect(admin.id, 'admin-123');
      expect(admin.username, 'admin');
      expect(admin.loginCount, 42);
      expect(admin.lastLoginAt, isNotNull);
    });

    test('toJson roundtrips correctly', () {
      final original = AdminUserInfo(
        id: 'admin-1',
        username: 'superadmin',
        createdAt: DateTime.utc(2024, 1, 1),
        loginCount: 100,
      );

      final json = original.toJson();
      final restored = AdminUserInfo.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.username, original.username);
      expect(restored.loginCount, original.loginCount);
    });
  });

  group('LoginAttempt', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'login-1',
        'admin_user_id': 'admin-123',
        'timestamp': '2024-01-15T10:30:00.000Z',
        'success': true,
        'ip_address': '192.168.1.1',
        'user_agent': 'Mozilla/5.0',
      };

      final attempt = LoginAttempt.fromJson(json);

      expect(attempt.id, 'login-1');
      expect(attempt.adminUserId, 'admin-123');
      expect(attempt.success, true);
      expect(attempt.ipAddress, '192.168.1.1');
      expect(attempt.userAgent, 'Mozilla/5.0');
    });

    test('isSuspicious detects brute force patterns', () {
      final suspiciousAttempt = LoginAttempt(
        id: 'login-1',
        adminUserId: 'admin-1',
        timestamp: DateTime.now(),
        success: false,
        failureReason: 'brute_force_detected',
      );

      expect(suspiciousAttempt.isSuspicious, true);
    });

    test('isSuspicious returns false for normal failures', () {
      final normalFailure = LoginAttempt(
        id: 'login-1',
        adminUserId: 'admin-1',
        timestamp: DateTime.now(),
        success: false,
        failureReason: 'wrong_password',
      );

      expect(normalFailure.isSuspicious, false);
    });

    test('isSuspicious returns false for success', () {
      final successfulLogin = LoginAttempt(
        id: 'login-1',
        adminUserId: 'admin-1',
        timestamp: DateTime.now(),
        success: true,
      );

      expect(successfulLogin.isSuspicious, false);
    });
  });

  group('TokenInfo', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'token-123',
        'name': 'My Token',
        'scopes': ['admin', 'publish:all'],
        'created_at': '2024-01-01T00:00:00.000Z',
        'expires_at': '2025-01-01T00:00:00.000Z',
      };

      final token = TokenInfo.fromJson(json);

      expect(token.id, 'token-123');
      expect(token.name, 'My Token');
      expect(token.scopes, ['admin', 'publish:all']);
      expect(token.expiresAt, isNotNull);
    });

    test('handles missing expiration', () {
      final json = {
        'id': 'token-123',
        'name': 'Permanent Token',
        'scopes': <String>[],
        'created_at': '2024-01-01T00:00:00.000Z',
      };

      final token = TokenInfo.fromJson(json);

      expect(token.expiresAt, isNull);
    });
  });

  group('SiteConfig', () {
    test('fromJson parses correctly', () {
      final json = {
        'base_url': 'https://pub.example.com',
        'listen_addr': '0.0.0.0:4920',
        'require_download_auth': true,
        'database_type': 'postgres',
        'storage_type': 's3',
        'max_upload_size_mb': 200,
        'allow_public_registration': false,
        'smtp_host': 'smtp.example.com',
        'smtp_port': 587,
        'smtp_from': 'noreply@example.com',
      };

      final config = SiteConfig.fromJson(json);

      expect(config.baseUrl, 'https://pub.example.com');
      expect(config.requireDownloadAuth, true);
      expect(config.databaseType, 'postgres');
      expect(config.storageType, 's3');
      expect(config.maxUploadSizeMb, 200);
      expect(config.allowPublicRegistration, false);
      expect(config.smtpHost, 'smtp.example.com');
      expect(config.smtpPort, 587);
    });

    test('copyWith creates modified copy', () {
      final original = const SiteConfig(
        baseUrl: 'http://localhost:4920',
        listenAddr: '0.0.0.0:4920',
        requireDownloadAuth: false,
        databaseType: 'sqlite',
        storageType: 'local',
        maxUploadSizeMb: 100,
        allowPublicRegistration: true,
      );

      final modified = original.copyWith(
        requireDownloadAuth: true,
        maxUploadSizeMb: 200,
      );

      expect(modified.baseUrl, original.baseUrl);
      expect(modified.requireDownloadAuth, true);
      expect(modified.maxUploadSizeMb, 200);
      expect(modified.allowPublicRegistration, original.allowPublicRegistration);
    });

    test('toJson roundtrips correctly', () {
      final original = const SiteConfig(
        baseUrl: 'https://pub.example.com',
        listenAddr: '0.0.0.0:8080',
        requireDownloadAuth: true,
        databaseType: 'postgres',
        storageType: 's3',
        maxUploadSizeMb: 150,
        allowPublicRegistration: false,
        smtpHost: 'mail.example.com',
        smtpPort: 465,
        smtpFrom: 'pub@example.com',
      );

      final json = original.toJson();
      final restored = SiteConfig.fromJson(json);

      expect(restored, original);
    });
  });

  group('RecentActivity', () {
    test('fromJson parses correctly', () {
      final json = {
        'id': 'activity-1',
        'type': 'package_published',
        'description': 'Published test_package 1.0.0',
        'timestamp': '2024-01-15T10:30:00.000Z',
        'actor_email': 'dev@example.com',
        'target_package': 'test_package',
      };

      final activity = RecentActivity.fromJson(json);

      expect(activity.id, 'activity-1');
      expect(activity.type, 'package_published');
      expect(activity.actorEmail, 'dev@example.com');
      expect(activity.targetPackage, 'test_package');
    });
  });

  group('TopPackage', () {
    test('fromJson parses correctly', () {
      final json = {
        'name': 'popular_package',
        'download_count': 10000,
        'latest_version': '3.0.0',
      };

      final pkg = TopPackage.fromJson(json);

      expect(pkg.name, 'popular_package');
      expect(pkg.downloadCount, 10000);
      expect(pkg.latestVersion, '3.0.0');
    });
  });
}
