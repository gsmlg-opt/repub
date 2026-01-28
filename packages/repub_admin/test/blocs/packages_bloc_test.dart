import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repub_model/repub_model.dart' as model;

import 'package:repub_admin/blocs/packages/packages_bloc.dart';
import 'package:repub_admin/blocs/packages/packages_event.dart';
import 'package:repub_admin/blocs/packages/packages_state.dart';
import 'package:repub_admin/services/admin_api_client.dart';

// Mock classes
class MockAdminApiClient extends Mock implements AdminApiClient {}

void main() {
  group('PackagesBloc', () {
    late MockAdminApiClient mockApiClient;
    late PackagesBloc packagesBloc;

    setUp(() {
      mockApiClient = MockAdminApiClient();
      packagesBloc = PackagesBloc(apiClient: mockApiClient);
    });

    tearDown(() {
      packagesBloc.close();
    });

    test('initial state is PackagesInitial', () {
      expect(packagesBloc.state, const PackagesInitial());
    });

    group('LoadHostedPackages', () {
      final testPackages = _createTestPackageListResponse([
        _createPackageInfo('test_package_1', '1.0.0'),
        _createPackageInfo('test_package_2', '2.0.0'),
      ]);

      blocTest<PackagesBloc, PackagesState>(
        'emits [PackagesLoading, PackagesLoaded] when LoadHostedPackages succeeds',
        build: () {
          when(() => mockApiClient.listHostedPackages(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => testPackages);
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadHostedPackages()),
        expect: () => [
          const PackagesLoading(PackageViewType.hosted),
          isA<PackagesLoaded>()
              .having((s) => s.viewType, 'viewType', PackageViewType.hosted)
              .having((s) => s.packages.length, 'packages count', 2)
              .having((s) => s.total, 'total', 2),
        ],
      );

      blocTest<PackagesBloc, PackagesState>(
        'emits [PackagesLoading, PackagesError] when LoadHostedPackages fails',
        build: () {
          when(() => mockApiClient.listHostedPackages(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenThrow(Exception('Network error'));
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadHostedPackages()),
        expect: () => [
          const PackagesLoading(PackageViewType.hosted),
          isA<PackagesError>()
              .having((s) => s.message, 'message', contains('Network error')),
        ],
      );

      blocTest<PackagesBloc, PackagesState>(
        'passes page and limit parameters correctly',
        build: () {
          when(() => mockApiClient.listHostedPackages(
                page: 2,
                limit: 10,
              )).thenAnswer((_) async => testPackages);
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadHostedPackages(page: 2, limit: 10)),
        verify: (_) {
          verify(() => mockApiClient.listHostedPackages(
                page: 2,
                limit: 10,
              )).called(1);
        },
      );
    });

    group('LoadCachedPackages', () {
      final testPackages = _createTestPackageListResponse([
        _createPackageInfo('cached_pkg_1', '1.0.0'),
      ]);

      blocTest<PackagesBloc, PackagesState>(
        'emits [PackagesLoading, PackagesLoaded] when LoadCachedPackages succeeds',
        build: () {
          when(() => mockApiClient.listCachedPackages(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => testPackages);
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadCachedPackages()),
        expect: () => [
          const PackagesLoading(PackageViewType.cached),
          isA<PackagesLoaded>()
              .having((s) => s.viewType, 'viewType', PackageViewType.cached)
              .having((s) => s.packages.length, 'packages count', 1),
        ],
      );

      blocTest<PackagesBloc, PackagesState>(
        'emits [PackagesLoading, PackagesError] when LoadCachedPackages fails',
        build: () {
          when(() => mockApiClient.listCachedPackages(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenThrow(Exception('Server error'));
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const LoadCachedPackages()),
        expect: () => [
          const PackagesLoading(PackageViewType.cached),
          isA<PackagesError>()
              .having((s) => s.message, 'message', contains('Server error')),
        ],
      );
    });

    group('DeletePackage', () {
      blocTest<PackagesBloc, PackagesState>(
        'emits [PackageOperationInProgress, PackageOperationSuccess, ...] when delete succeeds',
        build: () {
          when(() => mockApiClient.deletePackage('my_package'))
              .thenAnswer((_) async => DeleteResult(message: 'Deleted'));
          when(() => mockApiClient.listHostedPackages(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => _createTestPackageListResponse([]));
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const DeletePackage('my_package')),
        expect: () => [
          const PackageOperationInProgress('deleting', 'my_package'),
          isA<PackageOperationSuccess>()
              .having((s) => s.message, 'message', contains('my_package')),
          const PackagesLoading(PackageViewType.hosted),
          isA<PackagesLoaded>(),
        ],
      );

      blocTest<PackagesBloc, PackagesState>(
        'emits [PackageOperationInProgress, PackageOperationError] when delete fails',
        build: () {
          when(() => mockApiClient.deletePackage('my_package')).thenThrow(
              AdminApiException(statusCode: 404, message: 'Package not found'));
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const DeletePackage('my_package')),
        expect: () => [
          const PackageOperationInProgress('deleting', 'my_package'),
          isA<PackageOperationError>().having(
              (s) => s.message, 'message', contains('Failed to delete')),
        ],
      );
    });

    group('DiscontinuePackage', () {
      blocTest<PackagesBloc, PackagesState>(
        'emits success when discontinue succeeds',
        build: () {
          when(() => mockApiClient.discontinuePackage('pkg'))
              .thenAnswer((_) async {});
          when(() => mockApiClient.listHostedPackages(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => _createTestPackageListResponse([]));
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const DiscontinuePackage('pkg', true)),
        expect: () => [
          const PackageOperationInProgress('discontinuing', 'pkg'),
          isA<PackageOperationSuccess>()
              .having((s) => s.message, 'message', contains('discontinued')),
          const PackagesLoading(PackageViewType.hosted),
          isA<PackagesLoaded>(),
        ],
      );
    });

    group('ClearPackageCache', () {
      blocTest<PackagesBloc, PackagesState>(
        'emits success when clear cache succeeds',
        build: () {
          when(() => mockApiClient.clearCachedPackage('cached_pkg'))
              .thenAnswer((_) async => DeleteResult(
                    message: 'Deleted cached_pkg with 3 versions',
                    versionsDeleted: 3,
                  ));
          when(() => mockApiClient.listCachedPackages(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => _createTestPackageListResponse([]));
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const ClearPackageCache('cached_pkg')),
        expect: () => [
          const PackageOperationInProgress('clearing_cache', 'cached_pkg'),
          isA<PackageOperationSuccess>()
              .having((s) => s.message, 'message', contains('cached_pkg')),
          const PackagesLoading(PackageViewType.cached),
          isA<PackagesLoaded>(),
        ],
      );

      blocTest<PackagesBloc, PackagesState>(
        'emits error when clear cache fails',
        build: () {
          when(() => mockApiClient.clearCachedPackage('cached_pkg')).thenThrow(
              AdminApiException(statusCode: 404, message: 'Not found'));
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const ClearPackageCache('cached_pkg')),
        expect: () => [
          const PackageOperationInProgress('clearing_cache', 'cached_pkg'),
          isA<PackageOperationError>()
              .having((s) => s.message, 'message', contains('Failed to clear')),
        ],
      );
    });

    group('ClearAllCache', () {
      blocTest<PackagesBloc, PackagesState>(
        'emits success when clear all cache succeeds',
        build: () {
          when(() => mockApiClient.clearCache())
              .thenAnswer((_) async => ClearCacheResult(
                    message: 'Cleared 5 packages',
                    packagesDeleted: 5,
                    blobsDeleted: 10,
                  ));
          when(() => mockApiClient.listCachedPackages(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => _createTestPackageListResponse([]));
          return PackagesBloc(apiClient: mockApiClient);
        },
        act: (bloc) => bloc.add(const ClearAllCache()),
        expect: () => [
          const PackageOperationInProgress('clearing_cache', 'all'),
          const PackageOperationSuccess('All cache cleared successfully'),
          const PackagesLoading(PackageViewType.cached),
          isA<PackagesLoaded>(),
        ],
      );
    });

    group('SearchPackages', () {
      final testPackages = _createTestPackageListResponse([
        _createPackageInfo('search_result', '1.0.0'),
      ]);

      blocTest<PackagesBloc, PackagesState>(
        'triggers LoadHostedPackages with search query when in hosted view',
        build: () {
          when(() => mockApiClient.listHostedPackages(
                page: any(named: 'page'),
                limit: any(named: 'limit'),
              )).thenAnswer((_) async => testPackages);
          return PackagesBloc(apiClient: mockApiClient);
        },
        seed: () => PackagesLoaded(
          viewType: PackageViewType.hosted,
          packages: const [],
          total: 0,
          page: 1,
          limit: 20,
        ),
        act: (bloc) => bloc.add(const SearchPackages('test')),
        verify: (_) {
          verify(() => mockApiClient.listHostedPackages(
                page: 1,
                limit: 20,
              )).called(1);
        },
      );
    });
  });
}

// Helper functions to create test data

model.PackageInfo _createPackageInfo(String name, String version) {
  return model.PackageInfo(
    package: model.Package(
      name: name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    versions: [
      model.PackageVersion(
        packageName: name,
        version: version,
        pubspec: {'description': 'Test package $name'},
        archiveKey: 'archives/$name/$version.tar.gz',
        archiveSha256: 'abc123',
        publishedAt: DateTime.now(),
      ),
    ],
  );
}

PackageListResponse _createTestPackageListResponse(
    List<model.PackageInfo> packages) {
  return PackageListResponse(
    packages: packages,
    total: packages.length,
    page: 1,
    limit: 20,
  );
}
