import 'dart:io';

import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

void main() {
  group('Activity Log Integration Tests', () {
    late MetadataStore metadata;
    late Config config;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('repub_activity_test_');

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
      );

      metadata = await MetadataStore.create(config);
      await metadata.runMigrations();
    });

    tearDown(() async {
      await metadata.close();
      await tempDir.delete(recursive: true);
    });

    group('Activity Logging', () {
      test('can log user registration activity', () async {
        final userId = await metadata.createUser(
          email: 'newuser@example.com',
          passwordHash: 'hash',
        );

        final activityId = await metadata.logActivity(
          activityType: 'user_registered',
          actorType: 'user',
          actorId: userId,
          actorEmail: 'newuser@example.com',
        );

        expect(activityId, isNotEmpty);

        final activities = await metadata.getRecentActivity(limit: 10);
        expect(activities.any((a) => a.id == activityId), isTrue);
        expect(
          activities.firstWhere((a) => a.id == activityId).activityType,
          equals('user_registered'),
        );
      });

      test('can log package_published activity with metadata', () async {
        final userId = await metadata.createUser(
          email: 'publisher@example.com',
          passwordHash: 'hash',
        );

        final activityId = await metadata.logActivity(
          activityType: 'package_published',
          actorType: 'user',
          actorId: userId,
          actorEmail: 'publisher@example.com',
          targetType: 'package',
          targetId: 'my_package',
          metadata: {'version': '1.0.0'},
        );

        expect(activityId, isNotEmpty);

        final activities = await metadata.getRecentActivity(limit: 10);
        final activity = activities.firstWhere((a) => a.id == activityId);

        expect(activity.activityType, equals('package_published'));
        expect(activity.targetId, equals('my_package'));
        expect(activity.metadata?['version'], equals('1.0.0'));
      });

      test('can log admin_login activity', () async {
        final adminId = await metadata.createAdminUser(
          username: 'admin',
          passwordHash: 'test_hash_123',
        );

        final activityId = await metadata.logActivity(
          activityType: 'admin_login',
          actorType: 'admin',
          actorId: adminId,
          actorUsername: 'admin',
          ipAddress: '127.0.0.1',
        );

        expect(activityId, isNotEmpty);

        final activities = await metadata.getRecentActivity(limit: 10);
        final activity = activities.firstWhere((a) => a.id == activityId);

        expect(activity.activityType, equals('admin_login'));
        expect(activity.actorType, equals('admin'));
        expect(activity.ipAddress, equals('127.0.0.1'));
      });
    });

    group('Activity Retrieval', () {
      setUp(() async {
        // Create some test activities
        final userId = await metadata.createUser(
          email: 'test@example.com',
          passwordHash: 'hash',
        );

        // Log multiple activities of different types
        await metadata.logActivity(
          activityType: 'user_registered',
          actorType: 'user',
          actorId: userId,
          actorEmail: 'test@example.com',
        );
        await metadata.logActivity(
          activityType: 'package_published',
          actorType: 'user',
          actorId: userId,
          actorEmail: 'test@example.com',
          targetType: 'package',
          targetId: 'package_a',
          metadata: {'version': '1.0.0'},
        );
        await metadata.logActivity(
          activityType: 'package_published',
          actorType: 'user',
          actorId: userId,
          actorEmail: 'test@example.com',
          targetType: 'package',
          targetId: 'package_b',
          metadata: {'version': '2.0.0'},
        );
      });

      test('getRecentActivity respects limit parameter', () async {
        final activities = await metadata.getRecentActivity(limit: 2);
        expect(activities.length, equals(2));
      });

      test('getRecentActivity returns newest first', () async {
        final activities = await metadata.getRecentActivity(limit: 10);

        // Verify timestamps are in descending order
        for (var i = 0; i < activities.length - 1; i++) {
          expect(
            activities[i].timestamp.isAfter(activities[i + 1].timestamp) ||
                activities[i]
                    .timestamp
                    .isAtSameMomentAs(activities[i + 1].timestamp),
            isTrue,
          );
        }
      });

      test('getRecentActivity can filter by activityType', () async {
        final activities = await metadata.getRecentActivity(
          limit: 10,
          activityType: 'package_published',
        );

        expect(activities.isNotEmpty, isTrue);
        expect(
          activities.every((a) => a.activityType == 'package_published'),
          isTrue,
        );
      });

      test('getRecentActivity can filter by actorType', () async {
        // Add an admin activity
        final adminId = await metadata.createAdminUser(
          username: 'admin',
          passwordHash: 'test_hash_123',
        );
        await metadata.logActivity(
          activityType: 'admin_login',
          actorType: 'admin',
          actorId: adminId,
          actorUsername: 'admin',
        );

        final userActivities = await metadata.getRecentActivity(
          limit: 10,
          actorType: 'user',
        );

        final adminActivities = await metadata.getRecentActivity(
          limit: 10,
          actorType: 'admin',
        );

        expect(
          userActivities.every((a) => a.actorType == 'user'),
          isTrue,
        );
        expect(
          adminActivities.every((a) => a.actorType == 'admin'),
          isTrue,
        );
      });
    });

    group('Activity Description Generation', () {
      test('package_published generates correct description', () async {
        final userId = await metadata.createUser(
          email: 'publisher@example.com',
          passwordHash: 'hash',
        );

        await metadata.logActivity(
          activityType: 'package_published',
          actorType: 'user',
          actorId: userId,
          actorEmail: 'publisher@example.com',
          targetType: 'package',
          targetId: 'my_package',
          metadata: {'version': '1.0.0'},
        );

        final activities = await metadata.getRecentActivity(limit: 1);
        final activity = activities.first;

        expect(activity.description, contains('published'));
        expect(activity.description, contains('my_package'));
      });

      test('user_registered generates correct description', () async {
        await metadata.logActivity(
          activityType: 'user_registered',
          actorType: 'user',
          actorEmail: 'newuser@test.com',
        );

        final activities = await metadata.getRecentActivity(limit: 1);
        final activity = activities.first;

        expect(activity.description, contains('registered'));
        expect(activity.description, contains('newuser@test.com'));
      });

      test('admin_login generates correct description', () async {
        final adminId = await metadata.createAdminUser(
          username: 'superadmin',
          passwordHash: 'test_hash_123',
        );

        await metadata.logActivity(
          activityType: 'admin_login',
          actorType: 'admin',
          actorId: adminId,
          actorUsername: 'superadmin',
        );

        final activities = await metadata.getRecentActivity(limit: 1);
        final activity = activities.first;

        expect(activity.description, contains('logged in'));
        expect(activity.description, contains('superadmin'));
      });
    });
  });
}
