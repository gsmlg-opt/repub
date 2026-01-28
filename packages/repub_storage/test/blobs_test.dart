import 'dart:io';
import 'dart:typed_data';

import 'package:repub_model/repub_model.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:test/test.dart';

void main() {
  group('FileBlobStore', () {
    late FileBlobStore blobStore;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('blob_test_');
      blobStore = FileBlobStore(
        basePath: tempDir.path,
        baseUrl: 'http://localhost:4920',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('ensureReady', () {
      test('creates directory if not exists', () async {
        final nestedPath = '${tempDir.path}/nested/storage';
        final store = FileBlobStore(
          basePath: nestedPath,
          baseUrl: 'http://localhost',
        );

        await store.ensureReady();

        expect(await Directory(nestedPath).exists(), isTrue);
      });

      test('succeeds if directory already exists', () async {
        await blobStore.ensureReady();
        // Second call should also succeed
        await blobStore.ensureReady();

        expect(await tempDir.exists(), isTrue);
      });
    });

    group('archiveKey', () {
      test('generates correct key format', () {
        final key = blobStore.archiveKey('my_package', '1.0.0', 'abc123');

        expect(key, equals('hosted-packages/my_package/1.0.0/abc123.tar.gz'));
      });

      test('handles package names with underscores', () {
        final key = blobStore.archiveKey('my_great_package', '2.0.0', 'def456');

        expect(key, equals('hosted-packages/my_great_package/2.0.0/def456.tar.gz'));
      });

      test('handles prerelease versions', () {
        final key =
            blobStore.archiveKey('test_pkg', '1.0.0-beta.1', 'sha256hash');

        expect(key, equals('hosted-packages/test_pkg/1.0.0-beta.1/sha256hash.tar.gz'));
      });

      test('handles build metadata versions', () {
        final key =
            blobStore.archiveKey('test_pkg', '1.0.0+build.123', 'sha256hash');

        expect(key,
            equals('hosted-packages/test_pkg/1.0.0+build.123/sha256hash.tar.gz'));
      });
    });

    group('putArchive', () {
      test('writes file to correct location', () async {
        final key = 'hosted-packages/test_pkg/1.0.0/hash.tar.gz';
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);

        await blobStore.putArchive(key: key, data: data);

        final file = File('${tempDir.path}/$key');
        expect(await file.exists(), isTrue);
        expect(await file.readAsBytes(), equals(data));
      });

      test('creates nested directories', () async {
        final key = 'hosted-packages/deeply/nested/package/1.0.0/hash.tar.gz';
        final data = Uint8List.fromList([10, 20, 30]);

        await blobStore.putArchive(key: key, data: data);

        final file = File('${tempDir.path}/$key');
        expect(await file.exists(), isTrue);
      });

      test('overwrites existing file', () async {
        final key = 'hosted-packages/test_pkg/1.0.0/hash.tar.gz';
        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6, 7, 8]);

        await blobStore.putArchive(key: key, data: data1);
        await blobStore.putArchive(key: key, data: data2);

        final file = File('${tempDir.path}/$key');
        expect(await file.readAsBytes(), equals(data2));
      });

      test('handles empty data', () async {
        final key = 'hosted-packages/empty_pkg/1.0.0/hash.tar.gz';
        final data = Uint8List.fromList([]);

        await blobStore.putArchive(key: key, data: data);

        final file = File('${tempDir.path}/$key');
        expect(await file.exists(), isTrue);
        expect(await file.readAsBytes(), isEmpty);
      });

      test('handles large files', () async {
        final key = 'hosted-packages/large_pkg/1.0.0/hash.tar.gz';
        // Create 1MB of data
        final data = Uint8List(1024 * 1024);
        for (var i = 0; i < data.length; i++) {
          data[i] = i % 256;
        }

        await blobStore.putArchive(key: key, data: data);

        final file = File('${tempDir.path}/$key');
        expect(await file.length(), equals(1024 * 1024));
      });
    });

    group('getArchive', () {
      test('reads file correctly', () async {
        final key = 'hosted-packages/test_pkg/1.0.0/hash.tar.gz';
        final data = Uint8List.fromList([100, 200, 150, 75]);

        await blobStore.putArchive(key: key, data: data);
        final result = await blobStore.getArchive(key);

        expect(result, equals(data));
      });

      test('throws on missing file', () async {
        final key = 'hosted-packages/nonexistent/1.0.0/hash.tar.gz';

        expect(
          () => blobStore.getArchive(key),
          throwsA(isA<FileSystemException>()),
        );
      });
    });

    group('exists', () {
      test('returns true for existing file', () async {
        final key = 'hosted-packages/test_pkg/1.0.0/hash.tar.gz';
        await blobStore.putArchive(
            key: key, data: Uint8List.fromList([1, 2, 3]));

        expect(await blobStore.exists(key), isTrue);
      });

      test('returns false for non-existing file', () async {
        final key = 'hosted-packages/nonexistent/1.0.0/hash.tar.gz';

        expect(await blobStore.exists(key), isFalse);
      });

      test('returns false for non-existing directory', () async {
        final key = 'hosted-packages/no/such/path/hash.tar.gz';

        expect(await blobStore.exists(key), isFalse);
      });
    });

    group('delete', () {
      test('removes existing file', () async {
        final key = 'hosted-packages/test_pkg/1.0.0/hash.tar.gz';
        await blobStore.putArchive(
            key: key, data: Uint8List.fromList([1, 2, 3]));

        expect(await blobStore.exists(key), isTrue);
        await blobStore.delete(key);
        expect(await blobStore.exists(key), isFalse);
      });

      test('succeeds for non-existing file', () async {
        final key = 'hosted-packages/nonexistent/1.0.0/hash.tar.gz';

        // Should not throw
        await blobStore.delete(key);
      });
    });

    group('getDownloadUrl', () {
      test('returns correct API endpoint for packages', () async {
        final key = 'hosted-packages/my_package/1.0.0/hash.tar.gz';
        final url = await blobStore.getDownloadUrl(key);

        expect(
            url,
            equals(
                'http://localhost:4920/api/packages/my_package/versions/1.0.0/archive.tar.gz'));
      });

      test('handles base URL with trailing slash', () async {
        final store = FileBlobStore(
          basePath: tempDir.path,
          baseUrl: 'http://localhost:4920/',
        );
        final key = 'hosted-packages/my_package/2.0.0/hash.tar.gz';

        final url = await store.getDownloadUrl(key);

        // Should not have double slashes
        expect(
            url,
            equals(
                'http://localhost:4920/api/packages/my_package/versions/2.0.0/archive.tar.gz'));
      });

      test('returns fallback for non-package keys', () async {
        final key = 'other/path/file.txt';
        final url = await blobStore.getDownloadUrl(key);

        expect(
            url, equals('http://localhost:4920/storage/other/path/file.txt'));
      });
    });
  });

  group('FileBlobStore as cache', () {
    late FileBlobStore cacheStore;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('cache_test_');
      cacheStore = FileBlobStore(
        basePath: tempDir.path,
        baseUrl: 'http://localhost:4920',
        isCache: true,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('cache store works the same as regular store', () async {
      final key = 'cached-packages/cached_pkg/1.0.0/hash.tar.gz';
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);

      await cacheStore.putArchive(key: key, data: data);

      expect(await cacheStore.exists(key), isTrue);
      expect(await cacheStore.getArchive(key), equals(data));
    });
  });

  group('BlobStore.fromConfig', () {
    test('creates FileBlobStore when storagePath is set', () {
      final config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite::memory:',
        storagePath: '/tmp/test-storage',
        requirePublishAuth: true,
        requireDownloadAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: true,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      final store = BlobStore.fromConfig(config);

      expect(store, isA<FileBlobStore>());
    });

    test('throws when neither storage path nor S3 config provided', () {
      final config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite::memory:',
        storagePath: null,
        requirePublishAuth: true,
        requireDownloadAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: true,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      expect(
        () => BlobStore.fromConfig(config),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('BlobStore.cacheFromConfig', () {
    test('creates FileBlobStore for cache', () {
      final config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite::memory:',
        storagePath: '/tmp/test-storage',
        cachePath: '/tmp/test-cache',
        requirePublishAuth: true,
        requireDownloadAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: true,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      final cacheStore = BlobStore.cacheFromConfig(config);

      expect(cacheStore, isA<FileBlobStore>());
    });
  });

  group('Archive key generation edge cases', () {
    late FileBlobStore store;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('key_test_');
      store = FileBlobStore(
        basePath: tempDir.path,
        baseUrl: 'http://localhost',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('handles very long package names', () {
      final longName = 'a' * 100;
      final key = store.archiveKey(longName, '1.0.0', 'hash');

      expect(key, startsWith('hosted-packages/$longName'));
    });

    test('handles very long sha256 hashes', () {
      final longHash = 'a' * 64; // SHA256 is 64 hex chars
      final key = store.archiveKey('pkg', '1.0.0', longHash);

      expect(key, endsWith('$longHash.tar.gz'));
    });
  });

  group('File operations concurrency', () {
    late FileBlobStore store;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('concurrency_test_');
      store = FileBlobStore(
        basePath: tempDir.path,
        baseUrl: 'http://localhost',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('handles concurrent writes to different keys', () async {
      final futures = <Future>[];
      for (var i = 0; i < 10; i++) {
        final key = 'hosted-packages/pkg_$i/1.0.0/hash.tar.gz';
        final data = Uint8List.fromList(List.generate(100, (j) => i + j));
        futures.add(store.putArchive(key: key, data: data));
      }

      await Future.wait(futures);

      // Verify all files were written correctly
      for (var i = 0; i < 10; i++) {
        final key = 'hosted-packages/pkg_$i/1.0.0/hash.tar.gz';
        expect(await store.exists(key), isTrue);
        final data = await store.getArchive(key);
        expect(data[0], equals(i)); // First byte should be i
      }
    });
  });
}
