import 'dart:io';

import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

void main() {
  group('Monitoring Endpoints Integration Tests', () {
    late MetadataStore metadata;
    late Config config;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('repub_monitoring_test_');

      config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite:${tempDir.path}/test.db',
        storagePath: tempDir.path,
        requirePublishAuth: true,
        requireDownloadAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: false,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      metadata = await MetadataStore.create(config);
      await metadata.runMigrations();
    });

    tearDown(() async {
      await metadata.close();
      await tempDir.delete(recursive: true);
    });

    group('Health Check', () {
      test('healthCheck returns healthy status for valid database', () async {
        final result = await metadata.healthCheck();

        expect(result['status'], equals('healthy'));
        expect(result['latencyMs'], isA<num>());
        expect(result['latencyMs'], greaterThanOrEqualTo(0));
      });

      test('healthCheck returns database type', () async {
        final result = await metadata.healthCheck();

        expect(result['type'], equals('sqlite'));
      });

      test('healthCheck includes database size for SQLite', () async {
        final result = await metadata.healthCheck();

        // SQLite health check includes file size
        expect(result['dbSizeBytes'], isA<int>());
        expect(result['dbSizeBytes'], greaterThan(0));
      });
    });

    group('Stats Methods', () {
      test('countUsers returns correct count', () async {
        // Get initial count (may be non-zero if seeded)
        final initialCount = await metadata.countUsers();

        // Add a user
        await metadata.createUser(
          email: 'test@example.com',
          passwordHash: 'hash',
        );

        var count = await metadata.countUsers();
        expect(count, equals(initialCount + 1));

        // Add another user
        await metadata.createUser(
          email: 'test2@example.com',
          passwordHash: 'hash',
        );

        count = await metadata.countUsers();
        expect(count, equals(initialCount + 2));
      });

      test('countActiveTokens returns correct count', () async {
        final userId = await metadata.createUser(
          email: 'token@example.com',
          passwordHash: 'hash',
        );

        // Initially no tokens
        var count = await metadata.countActiveTokens();
        expect(count, equals(0));

        // Add an active token (no expiration)
        await metadata.createToken(
          userId: userId,
          label: 'Token 1',
          scopes: ['read:all'],
        );

        count = await metadata.countActiveTokens();
        expect(count, equals(1));

        // Add an expired token
        await metadata.createToken(
          userId: userId,
          label: 'Expired Token',
          scopes: ['read:all'],
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        );

        // Expired token should not be counted
        count = await metadata.countActiveTokens();
        expect(count, equals(1));

        // Add another active token
        await metadata.createToken(
          userId: userId,
          label: 'Token 2',
          scopes: ['publish:all'],
        );

        count = await metadata.countActiveTokens();
        expect(count, equals(2));
      });

      test('getTotalDownloads returns correct count', () async {
        // Initially no downloads
        var count = await metadata.getTotalDownloads();
        expect(count, equals(0));
      });

      test('getAdminStats returns comprehensive statistics', () async {
        // Create some test data
        final userId = await metadata.createUser(
          email: 'stats@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'Active Token',
          scopes: ['admin'],
        );

        // Get stats
        final stats = await metadata.getAdminStats();

        expect(stats.totalPackages, greaterThanOrEqualTo(0));
        expect(stats.localPackages, greaterThanOrEqualTo(0));
        expect(stats.cachedPackages, greaterThanOrEqualTo(0));
        expect(stats.totalVersions, greaterThanOrEqualTo(0));
        expect(stats.totalUsers, greaterThanOrEqualTo(1));
        expect(stats.activeTokens, greaterThanOrEqualTo(1));
        expect(stats.totalDownloads, greaterThanOrEqualTo(0));
      });

      test('getAdminStats totalUsers matches countUsers', () async {
        await metadata.createUser(
          email: 'match@example.com',
          passwordHash: 'hash',
        );

        final stats = await metadata.getAdminStats();
        final count = await metadata.countUsers();

        expect(stats.totalUsers, equals(count));
      });

      test('getAdminStats activeTokens matches countActiveTokens', () async {
        final userId = await metadata.createUser(
          email: 'match2@example.com',
          passwordHash: 'hash',
        );

        await metadata.createToken(
          userId: userId,
          label: 'Test Token',
          scopes: ['read:all'],
        );

        final stats = await metadata.getAdminStats();
        final count = await metadata.countActiveTokens();

        expect(stats.activeTokens, equals(count));
      });

      test('getAdminStats totalDownloads matches getTotalDownloads', () async {
        final stats = await metadata.getAdminStats();
        final count = await metadata.getTotalDownloads();

        expect(stats.totalDownloads, equals(count));
      });
    });

    group('AdminStats Model', () {
      test('AdminStats toJson includes all fields', () async {
        final stats = const AdminStats(
          totalPackages: 10,
          localPackages: 5,
          cachedPackages: 5,
          totalVersions: 20,
          totalUsers: 3,
          activeTokens: 8,
          totalDownloads: 100,
        );

        final json = stats.toJson();

        expect(json['totalPackages'], equals(10));
        expect(json['localPackages'], equals(5));
        expect(json['cachedPackages'], equals(5));
        expect(json['totalVersions'], equals(20));
        expect(json['totalUsers'], equals(3));
        expect(json['activeTokens'], equals(8));
        expect(json['totalDownloads'], equals(100));
      });

      test('AdminStats fromJson parses all fields', () async {
        final json = {
          'totalPackages': 15,
          'localPackages': 10,
          'cachedPackages': 5,
          'totalVersions': 30,
          'totalUsers': 7,
          'activeTokens': 12,
          'totalDownloads': 250,
        };

        final stats = AdminStats.fromJson(json);

        expect(stats.totalPackages, equals(15));
        expect(stats.localPackages, equals(10));
        expect(stats.cachedPackages, equals(5));
        expect(stats.totalVersions, equals(30));
        expect(stats.totalUsers, equals(7));
        expect(stats.activeTokens, equals(12));
        expect(stats.totalDownloads, equals(250));
      });

      test('AdminStats fromJson defaults new fields to 0', () async {
        // Simulate old API response without new fields
        final json = {
          'totalPackages': 5,
          'localPackages': 3,
          'cachedPackages': 2,
          'totalVersions': 10,
        };

        final stats = AdminStats.fromJson(json);

        expect(stats.totalPackages, equals(5));
        expect(stats.totalUsers, equals(0));
        expect(stats.activeTokens, equals(0));
        expect(stats.totalDownloads, equals(0));
      });

      test('AdminStats constructor uses default values', () async {
        final stats = const AdminStats(
          totalPackages: 1,
          localPackages: 1,
          cachedPackages: 0,
          totalVersions: 1,
        );

        expect(stats.totalUsers, equals(0));
        expect(stats.activeTokens, equals(0));
        expect(stats.totalDownloads, equals(0));
      });
    });
  });
}
