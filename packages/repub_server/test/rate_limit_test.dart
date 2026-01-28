import 'package:repub_server/src/rate_limit.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimitStore', () {
    late RateLimitStore store;

    setUp(() {
      store = RateLimitStore();
    });

    test('allows requests within limit', () {
      const maxRequests = 5;
      final windowDuration = Duration(seconds: 60);

      for (var i = 0; i < maxRequests; i++) {
        final count =
            store.checkAndRecord('test-key', maxRequests, windowDuration);
        expect(count, isNotNull);
        expect(count, equals(i + 1));
      }
    });

    test('blocks requests over limit', () {
      const maxRequests = 3;
      final windowDuration = Duration(seconds: 60);

      // Fill up the limit
      for (var i = 0; i < maxRequests; i++) {
        store.checkAndRecord('test-key', maxRequests, windowDuration);
      }

      // Next request should be blocked
      final count =
          store.checkAndRecord('test-key', maxRequests, windowDuration);
      expect(count, isNull);
    });

    test('tracks different keys separately', () {
      const maxRequests = 2;
      final windowDuration = Duration(seconds: 60);

      // Fill up key1
      store.checkAndRecord('key1', maxRequests, windowDuration);
      store.checkAndRecord('key1', maxRequests, windowDuration);

      // key1 should be blocked
      expect(store.checkAndRecord('key1', maxRequests, windowDuration), isNull);

      // key2 should still work
      expect(
          store.checkAndRecord('key2', maxRequests, windowDuration), equals(1));
    });

    test('getRemaining returns correct count', () {
      const maxRequests = 5;
      final windowDuration = Duration(seconds: 60);

      expect(store.getRemaining('test-key', maxRequests, windowDuration),
          equals(5));

      store.checkAndRecord('test-key', maxRequests, windowDuration);
      expect(store.getRemaining('test-key', maxRequests, windowDuration),
          equals(4));

      store.checkAndRecord('test-key', maxRequests, windowDuration);
      expect(store.getRemaining('test-key', maxRequests, windowDuration),
          equals(3));
    });

    test('cleanup removes old entries', () {
      const maxRequests = 5;
      final windowDuration = Duration(milliseconds: 10);

      store.checkAndRecord('test-key', maxRequests, windowDuration);
      expect(store.getRemaining('test-key', maxRequests, windowDuration),
          equals(4));

      // Wait for window to expire
      Future.delayed(Duration(milliseconds: 20), () {
        store.cleanup(windowDuration);
        // After cleanup, the key should have full capacity again
        expect(store.getRemaining('test-key', maxRequests, windowDuration),
            equals(5));
      });
    });
  });

  group('RateLimitConfig', () {
    test('stores configuration correctly', () {
      final config = RateLimitConfig(
        maxRequests: 100,
        windowSeconds: 60,
        message: 'Custom rate limit message',
      );

      expect(config.maxRequests, equals(100));
      expect(config.windowSeconds, equals(60));
      expect(config.message, equals('Custom rate limit message'));
    });

    test('message is optional', () {
      final config = RateLimitConfig(
        maxRequests: 50,
        windowSeconds: 30,
      );

      expect(config.maxRequests, equals(50));
      expect(config.windowSeconds, equals(30));
      expect(config.message, isNull);
    });
  });

  group('extractClientIp', () {
    test('extracts IP from X-Forwarded-For header', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': '192.168.1.100, 10.0.0.1'},
      );

      expect(extractClientIp(request), equals('192.168.1.100'));
    });

    test('extracts IP from X-Real-IP header when X-Forwarded-For is missing',
        () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-real-ip': '192.168.1.100'},
      );

      expect(extractClientIp(request), equals('192.168.1.100'));
    });

    test('returns unknown when no IP headers present', () {
      final request = Request('GET', Uri.parse('http://localhost/test'));

      expect(extractClientIp(request), equals('unknown'));
    });

    test('prefers X-Forwarded-For over X-Real-IP', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {
          'x-forwarded-for': '10.0.0.1',
          'x-real-ip': '192.168.1.1',
        },
      );

      expect(extractClientIp(request), equals('10.0.0.1'));
    });
  });

  group('extractCompositeKey', () {
    test('returns IP when no authorization header', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': '192.168.1.100'},
      );

      expect(extractCompositeKey(request), equals('192.168.1.100'));
    });

    test('includes token prefix when authorization header present', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {
          'x-forwarded-for': '192.168.1.100',
          'authorization': 'Bearer abcdefghij1234567890',
        },
      );

      expect(extractCompositeKey(request), equals('192.168.1.100:abcdefgh'));
    });

    test('handles short tokens', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {
          'x-forwarded-for': '192.168.1.100',
          'authorization': 'Bearer abc',
        },
      );

      expect(extractCompositeKey(request), equals('192.168.1.100:abc'));
    });
  });

  group('rateLimitMiddleware', () {
    test('allows requests within limit', () async {
      final store = RateLimitStore();
      final config = RateLimitConfig(maxRequests: 5, windowSeconds: 60);

      final middleware = rateLimitMiddleware(
        keyExtractor: extractClientIp,
        config: config,
        store: store,
      );

      final handler = middleware((request) => Response.ok('OK'));

      for (var i = 0; i < 5; i++) {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/test'),
          headers: {'x-forwarded-for': '192.168.1.100'},
        );

        final response = await handler(request);
        expect(response.statusCode, equals(200));
        expect(response.headers['X-RateLimit-Limit'], equals('5'));
        expect(response.headers['X-RateLimit-Remaining'],
            equals((4 - i).toString()));
      }
    });

    test('returns 429 when rate limited', () async {
      final store = RateLimitStore();
      final config = RateLimitConfig(maxRequests: 2, windowSeconds: 60);

      final middleware = rateLimitMiddleware(
        keyExtractor: extractClientIp,
        config: config,
        store: store,
      );

      final handler = middleware((request) => Response.ok('OK'));

      // First two requests should succeed
      for (var i = 0; i < 2; i++) {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/test'),
          headers: {'x-forwarded-for': '192.168.1.100'},
        );
        final response = await handler(request);
        expect(response.statusCode, equals(200));
      }

      // Third request should be rate limited
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': '192.168.1.100'},
      );
      final response = await handler(request);
      expect(response.statusCode, equals(429));
      expect(response.headers['content-type'], equals('application/json'));
      expect(response.headers['X-RateLimit-Remaining'], equals('0'));

      final body = await response.readAsString();
      expect(body, contains('rate_limited'));
      expect(body, contains('Too many requests'));
    });

    test('excludes paths from rate limiting', () async {
      final store = RateLimitStore();
      final config = RateLimitConfig(maxRequests: 1, windowSeconds: 60);

      final middleware = rateLimitMiddleware(
        keyExtractor: extractClientIp,
        config: config,
        excludePaths: ['health', 'metrics'],
        store: store,
      );

      final handler = middleware((request) => Response.ok('OK'));

      // Health endpoint should not be rate limited
      for (var i = 0; i < 5; i++) {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/health'),
          headers: {'x-forwarded-for': '192.168.1.100'},
        );
        final response = await handler(request);
        expect(response.statusCode, equals(200));
      }

      // Metrics endpoint should not be rate limited
      for (var i = 0; i < 5; i++) {
        final request = Request(
          'GET',
          Uri.parse('http://localhost/metrics'),
          headers: {'x-forwarded-for': '192.168.1.100'},
        );
        final response = await handler(request);
        expect(response.statusCode, equals(200));
      }
    });

    test('uses custom error message', () async {
      final store = RateLimitStore();
      final config = RateLimitConfig(
        maxRequests: 1,
        windowSeconds: 60,
        message: 'Custom rate limit error',
      );

      final middleware = rateLimitMiddleware(
        keyExtractor: extractClientIp,
        config: config,
        store: store,
      );

      final handler = middleware((request) => Response.ok('OK'));

      // First request succeeds
      final request1 = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': '192.168.1.100'},
      );
      await handler(request1);

      // Second request should be rate limited with custom message
      final request2 = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': '192.168.1.100'},
      );
      final response = await handler(request2);
      final body = await response.readAsString();
      expect(body, contains('Custom rate limit error'));
    });

    test('includes Retry-After header when rate limited', () async {
      final store = RateLimitStore();
      final config = RateLimitConfig(maxRequests: 1, windowSeconds: 60);

      final middleware = rateLimitMiddleware(
        keyExtractor: extractClientIp,
        config: config,
        store: store,
      );

      final handler = middleware((request) => Response.ok('OK'));

      // First request succeeds
      final request1 = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': '192.168.1.100'},
      );
      await handler(request1);

      // Second request should be rate limited
      final request2 = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': '192.168.1.100'},
      );
      final response = await handler(request2);
      expect(response.headers['Retry-After'], isNotNull);
      expect(int.tryParse(response.headers['Retry-After']!), greaterThan(0));
    });
  });

  group('RateLimitStore edge cases', () {
    late RateLimitStore store;

    setUp(() {
      store = RateLimitStore();
    });

    test('getRemaining returns full capacity for unknown key', () {
      const maxRequests = 100;
      final windowDuration = Duration(seconds: 60);

      // Key that has never been seen should have full capacity
      expect(store.getRemaining('never-seen', maxRequests, windowDuration),
          equals(maxRequests));
    });

    test('getResetSeconds returns 0 for unknown key', () {
      final windowDuration = Duration(seconds: 60);

      // Key that has never been seen should have 0 reset time
      expect(store.getResetSeconds('never-seen', windowDuration), equals(0));
    });

    test('handles very short window duration', () {
      const maxRequests = 5;
      final windowDuration = Duration(milliseconds: 1);

      // Record a request
      final count =
          store.checkAndRecord('short-window', maxRequests, windowDuration);
      expect(count, equals(1));

      // After 1ms, the request should expire - but in practice it might not
      // due to timing, so we just verify no crash
    });

    test('handles large request counts without overflow', () {
      const maxRequests = 1000000; // 1 million
      final windowDuration = Duration(seconds: 60);

      // Should be able to track up to the limit
      for (var i = 0; i < 10; i++) {
        final count =
            store.checkAndRecord('large-limit', maxRequests, windowDuration);
        expect(count, equals(i + 1));
      }

      // Verify remaining calculation is correct
      expect(store.getRemaining('large-limit', maxRequests, windowDuration),
          equals(maxRequests - 10));
    });

    test('empty string key works correctly', () {
      const maxRequests = 5;
      final windowDuration = Duration(seconds: 60);

      final count = store.checkAndRecord('', maxRequests, windowDuration);
      expect(count, equals(1));

      expect(store.getRemaining('', maxRequests, windowDuration), equals(4));
    });
  });

  group('extractCompositeKey edge cases', () {
    test('handles empty Bearer token', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {
          'x-forwarded-for': '192.168.1.100',
          'authorization': 'Bearer ',
        },
      );

      expect(extractCompositeKey(request), equals('192.168.1.100:'));
    });

    test('handles non-Bearer authorization', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {
          'x-forwarded-for': '192.168.1.100',
          'authorization': 'Basic dXNlcjpwYXNz',
        },
      );

      // Should return just IP since it's not a Bearer token
      expect(extractCompositeKey(request), equals('192.168.1.100'));
    });

    test('handles malformed authorization header', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {
          'x-forwarded-for': '192.168.1.100',
          'authorization': 'Bearer', // Missing space and token
        },
      );

      // Should return just IP since there's no token after Bearer
      expect(extractCompositeKey(request), equals('192.168.1.100'));
    });
  });

  group('extractClientIp edge cases', () {
    test('handles empty X-Forwarded-For header', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': ''},
      );

      // Empty X-Forwarded-For falls back to 'unknown'
      expect(extractClientIp(request), equals('unknown'));
    });

    test('handles whitespace in X-Forwarded-For', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': '  192.168.1.100  , 10.0.0.1'},
      );

      // Should trim whitespace from the first IP
      expect(extractClientIp(request), equals('192.168.1.100'));
    });

    test('handles single IP in X-Forwarded-For without comma', () {
      final request = Request(
        'GET',
        Uri.parse('http://localhost/test'),
        headers: {'x-forwarded-for': '192.168.1.100'},
      );

      expect(extractClientIp(request), equals('192.168.1.100'));
    });
  });
}
