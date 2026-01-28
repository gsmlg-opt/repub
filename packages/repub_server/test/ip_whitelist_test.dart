import 'package:repub_server/src/ip_whitelist.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('IP Whitelist Middleware', () {
    late Handler testHandler;

    setUp(() {
      testHandler = (Request request) async {
        return Response.ok('allowed');
      };
    });

    Request createRequest(String path, {String? ip, String? forwardedFor}) {
      final headers = <String, String>{};
      if (ip != null) {
        headers['x-real-ip'] = ip;
      }
      if (forwardedFor != null) {
        headers['x-forwarded-for'] = forwardedFor;
      }
      return Request('GET', Uri.parse('http://localhost$path'),
          headers: headers);
    }

    group('Empty whitelist', () {
      test('allows all requests when whitelist is empty', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: [],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        final response =
            await handler(createRequest('/admin/api/stats', ip: '1.2.3.4'));
        expect(response.statusCode, equals(200));
      });
    });

    group('Wildcard whitelist', () {
      test('allows all requests when whitelist contains *', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['*'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        final response =
            await handler(createRequest('/admin/api/stats', ip: '1.2.3.4'));
        expect(response.statusCode, equals(200));
      });
    });

    group('Exact IP matching', () {
      test('allows whitelisted IP', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.100'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        final response = await handler(
            createRequest('/admin/api/stats', ip: '192.168.1.100'));
        expect(response.statusCode, equals(200));
      });

      test('blocks non-whitelisted IP', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.100'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        final response = await handler(
            createRequest('/admin/api/stats', ip: '192.168.1.101'));
        expect(response.statusCode, equals(403));
      });

      test('allows localhost expansion', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['localhost'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        final response =
            await handler(createRequest('/admin/api/stats', ip: '127.0.0.1'));
        expect(response.statusCode, equals(200));
      });
    });

    group('CIDR matching', () {
      test('allows IP within CIDR range', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.0/24'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        // All 192.168.1.x addresses should be allowed
        var response =
            await handler(createRequest('/admin/api/stats', ip: '192.168.1.0'));
        expect(response.statusCode, equals(200));

        response =
            await handler(createRequest('/admin/api/stats', ip: '192.168.1.1'));
        expect(response.statusCode, equals(200));

        response = await handler(
            createRequest('/admin/api/stats', ip: '192.168.1.255'));
        expect(response.statusCode, equals(200));
      });

      test('blocks IP outside CIDR range', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.0/24'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        final response =
            await handler(createRequest('/admin/api/stats', ip: '192.168.2.1'));
        expect(response.statusCode, equals(403));
      });

      test('supports /16 CIDR range', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['10.0.0.0/16'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        var response =
            await handler(createRequest('/admin/api/stats', ip: '10.0.0.1'));
        expect(response.statusCode, equals(200));

        response = await handler(
            createRequest('/admin/api/stats', ip: '10.0.255.255'));
        expect(response.statusCode, equals(200));

        response =
            await handler(createRequest('/admin/api/stats', ip: '10.1.0.1'));
        expect(response.statusCode, equals(403));
      });

      test('supports /8 CIDR range', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['10.0.0.0/8'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        var response = await handler(
            createRequest('/admin/api/stats', ip: '10.255.255.255'));
        expect(response.statusCode, equals(200));

        response =
            await handler(createRequest('/admin/api/stats', ip: '11.0.0.1'));
        expect(response.statusCode, equals(403));
      });
    });

    group('Multiple whitelist entries', () {
      test('allows IP matching any entry', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.0/24', '10.0.0.0/8', '172.16.0.5'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        var response = await handler(
            createRequest('/admin/api/stats', ip: '192.168.1.50'));
        expect(response.statusCode, equals(200));

        response =
            await handler(createRequest('/admin/api/stats', ip: '10.10.10.10'));
        expect(response.statusCode, equals(200));

        response =
            await handler(createRequest('/admin/api/stats', ip: '172.16.0.5'));
        expect(response.statusCode, equals(200));
      });

      test('blocks IP not matching any entry', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.0/24', '10.0.0.0/8'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        final response =
            await handler(createRequest('/admin/api/stats', ip: '172.16.0.1'));
        expect(response.statusCode, equals(403));
      });
    });

    group('Path prefix filtering', () {
      test('only applies to paths with prefix', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.100'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        // Admin path should be blocked for non-whitelisted IP
        var response =
            await handler(createRequest('/admin/api/stats', ip: '1.2.3.4'));
        expect(response.statusCode, equals(403));

        // Non-admin path should be allowed
        response = await handler(createRequest('/api/packages', ip: '1.2.3.4'));
        expect(response.statusCode, equals(200));

        response = await handler(createRequest('/health', ip: '1.2.3.4'));
        expect(response.statusCode, equals(200));
      });
    });

    group('X-Forwarded-For header', () {
      test('uses first IP from X-Forwarded-For', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.100'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        // Client IP is first in the chain
        var response = await handler(createRequest(
          '/admin/api/stats',
          forwardedFor: '192.168.1.100, 10.0.0.1, 172.16.0.1',
        ));
        expect(response.statusCode, equals(200));

        // Client IP is not whitelisted
        response = await handler(createRequest(
          '/admin/api/stats',
          forwardedFor: '1.2.3.4, 192.168.1.100',
        ));
        expect(response.statusCode, equals(403));
      });
    });

    group('Unknown IP handling', () {
      test('blocks unknown IP', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.100'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        // No IP headers = 'unknown'
        final response = await handler(createRequest('/admin/api/stats'));
        expect(response.statusCode, equals(403));
      });

      test('allows unknown IP with wildcard', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['*'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        final response = await handler(createRequest('/admin/api/stats'));
        expect(response.statusCode, equals(200));
      });
    });

    group('Invalid whitelist entries', () {
      test('ignores invalid IP addresses', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['not-an-ip', '192.168.1.100', '256.256.256.256'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        // Valid entry should still work
        var response = await handler(
            createRequest('/admin/api/stats', ip: '192.168.1.100'));
        expect(response.statusCode, equals(200));

        // Invalid entries are ignored
        response =
            await handler(createRequest('/admin/api/stats', ip: 'not-an-ip'));
        expect(response.statusCode, equals(403));
      });

      test('ignores invalid CIDR notation', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.0/33', '10.0.0.0/8'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        // Valid CIDR should work
        var response =
            await handler(createRequest('/admin/api/stats', ip: '10.0.0.1'));
        expect(response.statusCode, equals(200));

        // Invalid CIDR is ignored
        response =
            await handler(createRequest('/admin/api/stats', ip: '192.168.1.1'));
        expect(response.statusCode, equals(403));
      });
    });

    group('Response format', () {
      test('returns JSON error for blocked requests', () async {
        final middleware = ipWhitelistMiddleware(
          whitelist: ['192.168.1.100'],
          pathPrefix: '/admin',
        );
        final handler = middleware(testHandler);

        final response =
            await handler(createRequest('/admin/api/stats', ip: '1.2.3.4'));
        expect(response.statusCode, equals(403));
        expect(response.headers['content-type'], equals('application/json'));

        final body = await response.readAsString();
        expect(body, contains('IP address not whitelisted'));
      });
    });
  });
}
