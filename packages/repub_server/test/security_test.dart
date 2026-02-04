import 'dart:convert';

import 'package:repub_model/repub_model.dart';
import 'package:repub_server/src/handlers.dart';
import 'package:repub_server/src/password_crypto.dart';
import 'package:repub_storage/repub_storage.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('Security Tests', () {
    late SqliteMetadataStore metadata;
    late BlobStore blobs;
    late BlobStore cacheBlobs;
    late Config config;
    late ApiHandlers handlers;

    setUp(() async {
      metadata = SqliteMetadataStore.inMemory();
      await metadata.runMigrations();

      // Create minimal blob stores (using file-based storage)
      blobs = FileBlobStore(
          basePath: '/tmp/repub_test_blobs', baseUrl: 'http://localhost:4920');
      cacheBlobs = FileBlobStore(
          basePath: '/tmp/repub_test_cache',
          baseUrl: 'http://localhost:4920',
          isCache: true);

      config = Config(
        listenAddr: '0.0.0.0',
        listenPort: 4920,
        baseUrl: 'http://localhost:4920',
        databaseUrl: 'sqlite::memory:',
        storagePath: '/tmp/repub_test_blobs',
        requirePublishAuth: true,
        requireDownloadAuth: false,
        signedUrlTtlSeconds: 3600,
        upstreamUrl: 'https://pub.dev',
        enableUpstreamProxy: false,
        rateLimitRequests: 100,
        rateLimitWindowSeconds: 60,
      );

      handlers = ApiHandlers(
        config: config,
        metadata: metadata,
        blobs: blobs,
        cacheBlobs: cacheBlobs,
        passwordCrypto: PasswordCrypto(),
      );
    });

    tearDown(() async {
      await metadata.close();
    });

    group('Email Validation', () {
      test('rejects empty email', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': '',
            'password': 'ValidPass123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('missing_email'));
      });

      test('rejects email without @ symbol', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'invalid-email.com',
            'password': 'ValidPass123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_email'));
      });

      test('rejects email without domain', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'test@',
            'password': 'ValidPass123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_email'));
      });

      test('rejects email with invalid TLD', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'test@example.c',
            'password': 'ValidPass123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_email'));
      });

      test('accepts valid email format', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'valid.user+test@example.com',
            'password': 'ValidPass123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        // Should succeed or fail for other reasons (not email validation)
        if (response.statusCode == 400) {
          final body = jsonDecode(await response.readAsString());
          expect(body['error']['code'], isNot(equals('invalid_email')));
        }
      });
    });

    group('Password Complexity', () {
      test('rejects password shorter than 8 characters', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'test1@example.com',
            'password': 'Short1',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('weak_password'));
        expect(body['error']['message'], contains('8 characters'));
      });

      test('rejects password without uppercase', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'test2@example.com',
            'password': 'lowercase123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('weak_password'));
        expect(body['error']['message'], contains('uppercase'));
      });

      test('rejects password without lowercase', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'test3@example.com',
            'password': 'UPPERCASE123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('weak_password'));
        expect(body['error']['message'], contains('lowercase'));
      });

      test('rejects password without numbers', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'test4@example.com',
            'password': 'NoNumbersHere',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('weak_password'));
        expect(body['error']['message'], contains('numbers'));
      });

      test('accepts password meeting all complexity requirements', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'test5@example.com',
            'password': 'ValidPass123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        // Should succeed (200) since password meets requirements
        expect(response.statusCode, equals(200));
      });
    });

    group('SSRF Protection - Webhook URL Validation', () {
      late String adminSessionId;

      setUp(() async {
        // Create admin user and session for webhook tests
        final adminId = await metadata.createAdminUser(
          username: 'admin',
          passwordHash: 'hash',
        );
        final session = await metadata.createAdminSession(
          adminUserId: adminId,
        );
        adminSessionId = session.sessionId;
      });

      test('blocks localhost webhook URL', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'http://localhost:8080/webhook',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_url'));
        expect(body['error']['message'], contains('internal'));
      });

      test('blocks 127.0.0.1 webhook URL', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'http://127.0.0.1:8080/webhook',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_url'));
      });

      test('blocks 10.x.x.x private network URL', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'http://10.0.0.5:8080/webhook',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_url'));
      });

      test('blocks 192.168.x.x private network URL', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'http://192.168.1.100/webhook',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_url'));
      });

      test('blocks 172.16-31.x.x private network URL', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'http://172.16.0.1/webhook',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_url'));
      });

      test('blocks 169.254.x.x link-local URL (AWS metadata)', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'http://169.254.169.254/latest/meta-data/',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_url'));
      });

      test('blocks IPv6 localhost ::1', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'http://[::1]:8080/webhook',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_url'));
      });

      test('allows valid external webhook URL', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'https://webhook.example.com/hook',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(200));
      });

      test('rejects non-HTTP/HTTPS protocol', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'ftp://ftp.example.com/webhook',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('invalid_url'));
        expect(body['error']['message'], contains('HTTP'));
      });

      test('allows 172.x.x.x outside private range', () async {
        // 172.32.0.1 is outside the 172.16-31 private range
        final request = Request(
          'POST',
          Uri.parse('http://localhost/admin/api/webhooks'),
          body: jsonEncode({
            'url': 'http://172.32.0.1/webhook',
            'events': ['package.published'],
          }),
          headers: {
            'content-type': 'application/json',
            'cookie': 'admin_session=$adminSessionId',
          },
        );

        final response = await handlers.adminCreateWebhook(request);
        expect(response.statusCode, equals(200));
      });
    });

    group('User Registration Security', () {
      test('prevents duplicate email registration', () async {
        // First registration
        final request1 = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'duplicate@example.com',
            'password': 'ValidPass123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response1 = await handlers.authRegister(request1);
        expect(response1.statusCode, equals(200));

        // Duplicate registration
        final request2 = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'email': 'duplicate@example.com',
            'password': 'AnotherPass123',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response2 = await handlers.authRegister(request2);
        expect(response2.statusCode, equals(409));
        final body = jsonDecode(await response2.readAsString());
        expect(body['error']['code'], equals('email_exists'));
      });

      test('handles malformed JSON gracefully', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: 'not valid json',
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
      });

      test('requires email and password fields', () async {
        final request = Request(
          'POST',
          Uri.parse('http://localhost/api/auth/register'),
          body: jsonEncode({
            'name': 'Just a name',
          }),
          headers: {'content-type': 'application/json'},
        );

        final response = await handlers.authRegister(request);
        expect(response.statusCode, equals(400));
        final body = jsonDecode(await response.readAsString());
        expect(body['error']['code'], equals('missing_email'));
      });
    });
  });
}
