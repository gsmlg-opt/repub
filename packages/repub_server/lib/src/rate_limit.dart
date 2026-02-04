import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Rate limit configuration.
class RateLimitConfig {
  /// Maximum number of requests per window.
  final int maxRequests;

  /// Window duration in seconds.
  final int windowSeconds;

  /// Optional message to include in rate limit responses.
  final String? message;

  const RateLimitConfig({
    required this.maxRequests,
    required this.windowSeconds,
    this.message,
  });
}

/// In-memory rate limit store using sliding window algorithm.
class RateLimitStore {
  final Map<String, List<DateTime>> _requests = {};

  /// Clean up old entries periodically.
  void cleanup(Duration windowDuration) {
    final cutoff = DateTime.now().subtract(windowDuration);
    _requests.forEach((key, timestamps) {
      timestamps.removeWhere((t) => t.isBefore(cutoff));
    });
    _requests.removeWhere((_, timestamps) => timestamps.isEmpty);
  }

  /// Check if a key is rate limited and record the request.
  /// Returns the number of requests in the current window, or null if rate limited.
  int? checkAndRecord(String key, int maxRequests, Duration windowDuration) {
    final now = DateTime.now();
    final cutoff = now.subtract(windowDuration);

    // Get or create request list for this key
    final timestamps = _requests.putIfAbsent(key, () => []);

    // Remove old timestamps outside the window
    timestamps.removeWhere((t) => t.isBefore(cutoff));

    // Check if rate limited
    if (timestamps.length >= maxRequests) {
      return null; // Rate limited
    }

    // Record this request
    timestamps.add(now);
    return timestamps.length;
  }

  /// Get remaining requests for a key.
  int getRemaining(String key, int maxRequests, Duration windowDuration) {
    final cutoff = DateTime.now().subtract(windowDuration);
    final timestamps = _requests[key];
    if (timestamps == null) return maxRequests;

    final validCount = timestamps.where((t) => t.isAfter(cutoff)).length;
    return maxRequests - validCount;
  }

  /// Get seconds until the rate limit resets for a key.
  int getResetSeconds(String key, Duration windowDuration) {
    final timestamps = _requests[key];
    if (timestamps == null || timestamps.isEmpty) return 0;

    final oldest = timestamps.reduce((a, b) => a.isBefore(b) ? a : b);
    final resetTime = oldest.add(windowDuration);
    final remaining = resetTime.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }
}

/// Global rate limit store.
final _globalStore = RateLimitStore();

/// Creates a rate limiting middleware.
///
/// The [keyExtractor] function extracts a unique key from each request
/// (typically the client IP address or API token).
///
/// The [config] specifies the rate limit parameters.
///
/// If [excludePaths] is provided, requests to those paths will not be rate limited.
Middleware rateLimitMiddleware({
  required String Function(Request) keyExtractor,
  required RateLimitConfig config,
  List<String>? excludePaths,
  RateLimitStore? store,
}) {
  final limitStore = store ?? _globalStore;
  final windowDuration = Duration(seconds: config.windowSeconds);

  // Periodically cleanup old entries (every 5 minutes)
  Timer.periodic(const Duration(minutes: 5), (_) {
    limitStore.cleanup(windowDuration);
  });

  return (Handler innerHandler) {
    return (Request request) async {
      // Skip rate limiting if maxRequests is 0 or less (unlimited)
      if (config.maxRequests <= 0) {
        return innerHandler(request);
      }

      // Check if path is excluded
      final path = request.url.path;
      if (excludePaths != null) {
        for (final excluded in excludePaths) {
          if (path.startsWith(excluded)) {
            return innerHandler(request);
          }
        }
      }

      // Extract key for rate limiting
      final key = keyExtractor(request);

      // Check rate limit
      final count = limitStore.checkAndRecord(
        key,
        config.maxRequests,
        windowDuration,
      );

      // Get rate limit headers
      final remaining = count != null ? config.maxRequests - count : 0;
      final resetSeconds = limitStore.getResetSeconds(key, windowDuration);

      final rateLimitHeaders = {
        'X-RateLimit-Limit': config.maxRequests.toString(),
        'X-RateLimit-Remaining': remaining.toString(),
        'X-RateLimit-Reset': resetSeconds.toString(),
      };

      if (count == null) {
        // Rate limited
        return Response(
          429,
          headers: {
            'content-type': 'application/json',
            'Retry-After': resetSeconds.toString(),
            ...rateLimitHeaders,
          },
          body: jsonEncode({
            'error': {
              'code': 'rate_limited',
              'message': config.message ??
                  'Too many requests. Please try again in $resetSeconds seconds.',
            },
          }),
        );
      }

      // Not rate limited - pass through and add headers
      final response = await innerHandler(request);
      return response.change(headers: rateLimitHeaders);
    };
  };
}

/// Extract client IP from request.
/// Checks X-Forwarded-For header first, then falls back to connection info.
String extractClientIp(Request request) {
  // Check for forwarded header (when behind reverse proxy)
  final forwarded = request.headers['x-forwarded-for'];
  if (forwarded != null && forwarded.isNotEmpty) {
    // Take the first IP in the list (original client)
    return forwarded.split(',').first.trim();
  }

  // Check for X-Real-IP header
  final realIp = request.headers['x-real-ip'];
  if (realIp != null && realIp.isNotEmpty) {
    return realIp;
  }

  // Fall back to unknown (actual IP not available in shelf without socket info)
  return 'unknown';
}

/// Create a composite key from IP and optional token.
String extractCompositeKey(Request request) {
  final ip = extractClientIp(request);
  final auth = request.headers['authorization'];
  if (auth != null && auth.startsWith('Bearer ')) {
    // Use first 8 chars of token hash for privacy
    final token = auth.substring(7);
    final tokenPrefix = token.length > 8 ? token.substring(0, 8) : token;
    return '$ip:$tokenPrefix';
  }
  return ip;
}
