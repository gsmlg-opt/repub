import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:repub_admin/models/package_stats.dart';
import 'package:repub_admin/services/admin_api_client.dart';

void main() {
  group('PackageStats', () {
    test('fromJson parses correctly', () {
      final json = {
        'package': {
          'name': 'test_package',
        },
        'version_count': 5,
        'latest_version': '2.0.0',
        'stats': {
          'package_name': 'test_package',
          'total_downloads': 1500,
          'downloads_by_version': {
            '2.0.0': 800,
            '1.0.0': 700,
          },
          'daily_downloads': {
            '2024-01-28': 100,
            '2024-01-27': 150,
            '2024-01-26': 80,
          },
        },
      };

      final stats = PackageStats.fromJson(json);

      expect(stats.packageName, equals('test_package'));
      expect(stats.totalDownloads, equals(1500));
      expect(stats.versionCount, equals(5));
      expect(stats.latestVersion, equals('2.0.0'));
      expect(stats.downloadsByVersion.length, equals(2));
      expect(stats.downloadsByVersion['2.0.0'], equals(800));
      expect(stats.dailyDownloads.length, equals(3));
      expect(stats.dailyDownloads['2024-01-28'], equals(100));
    });

    test('fromJson handles missing optional fields', () {
      final json = {
        'package': {'name': 'test_package'},
        'stats': {
          'package_name': 'test_package',
          'total_downloads': 0,
        },
      };

      final stats = PackageStats.fromJson(json);

      expect(stats.packageName, equals('test_package'));
      expect(stats.totalDownloads, equals(0));
      expect(stats.versionCount, equals(0));
      expect(stats.latestVersion, isNull);
      expect(stats.downloadsByVersion, isEmpty);
      expect(stats.dailyDownloads, isEmpty);
    });

    test('fromJson handles empty stats', () {
      final json = {
        'package': {'name': 'empty_package'},
        'version_count': 1,
        'latest_version': '1.0.0',
        'stats': <String, dynamic>{},
      };

      final stats = PackageStats.fromJson(json);

      // packageName comes from package.name, not stats
      expect(stats.packageName, equals('empty_package'));
      expect(stats.totalDownloads, equals(0));
      expect(stats.downloadsByVersion, isEmpty);
      expect(stats.dailyDownloads, isEmpty);
    });
  });

  group('AdminApiClient getPackageStats', () {
    late AdminApiClient apiClient;

    AdminApiClient createClient(http.Response Function(http.Request) handler) {
      final mockClient = MockClient((request) async => handler(request));
      return AdminApiClient.forTesting(
        baseUrl: 'http://localhost:4920',
        httpClient: mockClient,
      );
    }

    test('getPackageStats returns package statistics', () async {
      apiClient = createClient((request) {
        expect(request.url.path, equals('/admin/api/packages/my_package/stats'));
        expect(request.url.queryParameters['days'], equals('30'));

        return http.Response(
          jsonEncode({
            'package': {
              'name': 'my_package',
              'description': 'A test package',
              'created_at': '2024-01-01T00:00:00Z',
              'is_discontinued': false,
            },
            'version_count': 3,
            'latest_version': '1.2.0',
            'stats': {
              'package_name': 'my_package',
              'total_downloads': 500,
              'downloads_by_version': {
                '1.2.0': 300,
                '1.1.0': 150,
                '1.0.0': 50,
              },
              'daily_downloads': {
                '2024-01-28': 50,
                '2024-01-27': 45,
              },
            },
          }),
          200,
        );
      });

      final response = await apiClient.getPackageStats('my_package', days: 30);

      expect(response['package']?['name'], equals('my_package'));
      expect(response['version_count'], equals(3));
      expect(response['stats']?['total_downloads'], equals(500));
    });

    test('getPackageStats with custom days parameter', () async {
      apiClient = createClient((request) {
        expect(request.url.queryParameters['days'], equals('7'));
        return http.Response(
          jsonEncode({
            'package': {'name': 'test'},
            'stats': {'total_downloads': 100},
          }),
          200,
        );
      });

      await apiClient.getPackageStats('test', days: 7);
    });

    test('getPackageStats throws on 404', () async {
      apiClient = createClient((request) {
        return http.Response(
          jsonEncode({
            'error': {'code': 'not_found', 'message': 'Package not found'},
          }),
          404,
        );
      });

      expect(
        () => apiClient.getPackageStats('nonexistent'),
        throwsA(isA<AdminApiException>().having(
          (e) => e.statusCode,
          'statusCode',
          404,
        )),
      );
    });

    test('getPackageStats throws on server error', () async {
      apiClient = createClient((request) {
        return http.Response('Internal server error', 500);
      });

      expect(
        () => apiClient.getPackageStats('test'),
        throwsA(isA<AdminApiException>()),
      );
    });
  });

  group('PackageStats equatable', () {
    test('two PackageStats with same values are equal', () {
      final stats1 = PackageStats(
        packageName: 'test',
        totalDownloads: 100,
        downloadsByVersion: {'1.0.0': 100},
        dailyDownloads: {'2024-01-28': 50},
        versionCount: 1,
        latestVersion: '1.0.0',
      );

      final stats2 = PackageStats(
        packageName: 'test',
        totalDownloads: 100,
        downloadsByVersion: {'1.0.0': 100},
        dailyDownloads: {'2024-01-28': 50},
        versionCount: 1,
        latestVersion: '1.0.0',
      );

      expect(stats1, equals(stats2));
    });

    test('two PackageStats with different values are not equal', () {
      final stats1 = PackageStats(
        packageName: 'test1',
        totalDownloads: 100,
        downloadsByVersion: {},
        dailyDownloads: {},
        versionCount: 1,
      );

      final stats2 = PackageStats(
        packageName: 'test2',
        totalDownloads: 100,
        downloadsByVersion: {},
        dailyDownloads: {},
        versionCount: 1,
      );

      expect(stats1, isNot(equals(stats2)));
    });
  });
}
