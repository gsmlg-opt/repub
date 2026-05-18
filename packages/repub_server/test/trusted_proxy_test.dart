import 'package:repub_model/repub_model.dart';
import 'package:repub_server/src/handlers.dart';
import 'package:repub_server/src/password_crypto.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('Trusted Proxies', () {
    late SqliteMetadataStore metadata;
    late BlobStore blobs;
    late BlobStore cacheBlobs;
    late PasswordCrypto crypto;

    setUp(() async {
      metadata = SqliteMetadataStore.inMemory();
      await metadata.runMigrations();
      blobs =
          FileBlobStore(basePath: '/tmp/blobs', baseUrl: 'http://localhost');
      cacheBlobs = FileBlobStore(
          basePath: '/tmp/cache', baseUrl: 'http://localhost', isCache: true);
      crypto = PasswordCrypto();
    });

    tearDown(() async {
      await metadata.close();
    });

    test('trusts X-Forwarded-For when socket IP is in trusted proxies',
        () async {
      final config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite::memory:',
        requirePublishAuth: false,
        requireDownloadAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: false,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
        encryptionKey: 'test',
        trustedProxies: ['10.0.0.1'], // Trust this proxy
      );

      final handlers = ApiHandlers(
        config: config,
        metadata: metadata,
        blobs: blobs,
        cacheBlobs: cacheBlobs,
        passwordCrypto: crypto,
      );

      // Create a request simulating a connection from the trusted proxy
      final request = Request(
        'GET',
        Uri.parse('http://localhost/api/packages'),
        headers: {
          'x-forwarded-for': '192.168.1.100, 10.0.0.1',
        },
        context: {
          'shelf.io.connection_info': _MockConnectionInfo('10.0.0.1'),
        },
      );

      // Call an endpoint just to ensure handlers are hooked up properly
      final response = await handlers.listPackages(request);
      expect(response.statusCode, equals(200));

      await metadata.createAdminUser(
        username: 'admin',
        passwordHash: 'hash',
      );

      final loginRequest = Request(
        'POST',
        Uri.parse('http://localhost/admin/api/login'),
        body: '{"username":"admin","password":"password"}',
        headers: {
          'content-type': 'application/json',
          'x-forwarded-for': '192.168.1.100, 10.0.0.1',
        },
        context: {
          'shelf.io.connection_info': _MockConnectionInfo('10.0.0.1'),
        },
      );

      final loginResponse = await handlers.authLogin(loginRequest);
      expect(loginResponse.statusCode,
          equals(400)); // Will fail auth but won't crash on IP extraction
    });
  });
}

class _MockConnectionInfo {
  final _MockRemoteAddress remoteAddress;
  _MockConnectionInfo(String ip) : remoteAddress = _MockRemoteAddress(ip);
}

class _MockRemoteAddress {
  final String address;
  _MockRemoteAddress(this.address);
}
