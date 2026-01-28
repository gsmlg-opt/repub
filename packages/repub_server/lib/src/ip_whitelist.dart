import 'package:shelf/shelf.dart';

import 'rate_limit.dart' show extractClientIp;

/// IP whitelist middleware for restricting access to admin endpoints.
///
/// When a non-empty whitelist is provided, only requests from whitelisted
/// IP addresses will be allowed to access paths matching [pathPrefix].
///
/// The whitelist supports:
/// - IPv4 addresses (e.g., '192.168.1.100')
/// - IPv4 CIDR ranges (e.g., '192.168.1.0/24')
/// - IPv6 addresses (e.g., '::1', '2001:db8::1')
/// - Special value 'localhost' (expands to '127.0.0.1' and '::1')
/// - Special value '*' (allows all IPs, effectively disabling whitelist)
///
/// Example:
/// ```dart
/// final middleware = ipWhitelistMiddleware(
///   whitelist: ['127.0.0.1', '192.168.1.0/24', '10.0.0.0/8'],
///   pathPrefix: '/admin',
/// );
/// ```
Middleware ipWhitelistMiddleware({
  required List<String> whitelist,
  required String pathPrefix,
}) {
  // Expand special values and parse CIDRs
  final parsedRules = _parseWhitelist(whitelist);

  return (Handler handler) {
    return (Request request) {
      // If whitelist is empty or contains wildcard, allow all
      if (parsedRules.isEmpty || parsedRules.any((r) => r.allowsAll)) {
        return handler(request);
      }

      // Only check paths matching the prefix
      final path = request.requestedUri.path;
      if (!path.startsWith(pathPrefix)) {
        return handler(request);
      }

      // Extract client IP
      final clientIp = extractClientIp(request);

      // Check if IP is whitelisted
      if (_isIpWhitelisted(clientIp, parsedRules)) {
        return handler(request);
      }

      // IP not whitelisted
      return Response.forbidden(
        '{"error": "Access denied: IP address not whitelisted"}',
        headers: {'content-type': 'application/json'},
      );
    };
  };
}

/// Parsed whitelist rule that can match IPs.
abstract class _WhitelistRule {
  bool matches(String ip);
  bool get allowsAll => false;
}

/// Rule that matches a single exact IP address.
class _ExactIpRule extends _WhitelistRule {
  final String ip;
  _ExactIpRule(this.ip);

  @override
  bool matches(String clientIp) => clientIp == ip;
}

/// Rule that matches IPs within a CIDR range.
class _CidrRule extends _WhitelistRule {
  final int networkAddress;
  final int subnetMask;

  _CidrRule(this.networkAddress, this.subnetMask);

  @override
  bool matches(String clientIp) {
    final clientAddr = _parseIpv4(clientIp);
    if (clientAddr == null) return false;
    return (clientAddr & subnetMask) == (networkAddress & subnetMask);
  }
}

/// Rule that allows all IPs (wildcard).
class _WildcardRule extends _WhitelistRule {
  @override
  bool matches(String ip) => true;

  @override
  bool get allowsAll => true;
}

/// Parse whitelist strings into rules.
List<_WhitelistRule> _parseWhitelist(List<String> whitelist) {
  final rules = <_WhitelistRule>[];

  for (final entry in whitelist) {
    final trimmed = entry.trim().toLowerCase();

    if (trimmed.isEmpty) continue;

    // Wildcard: allow all
    if (trimmed == '*') {
      rules.add(_WildcardRule());
      continue;
    }

    // Localhost expansion (IPv4 and IPv6)
    if (trimmed == 'localhost') {
      rules.add(_ExactIpRule('127.0.0.1'));
      rules.add(_ExactIpRule('::1'));
      continue;
    }

    // CIDR notation
    if (trimmed.contains('/')) {
      final cidrRule = _parseCidr(trimmed);
      if (cidrRule != null) {
        rules.add(cidrRule);
      }
      continue;
    }

    // Exact IP address (IPv4 or IPv6)
    if (_isValidIpv4(trimmed) || _isValidIpv6(trimmed)) {
      rules.add(_ExactIpRule(trimmed));
    }
  }

  return rules;
}

/// Parse CIDR notation (e.g., "192.168.1.0/24").
_CidrRule? _parseCidr(String cidr) {
  final parts = cidr.split('/');
  if (parts.length != 2) return null;

  final ip = parts[0];
  final prefixLength = int.tryParse(parts[1]);

  if (prefixLength == null || prefixLength < 0 || prefixLength > 32) {
    return null;
  }

  final networkAddr = _parseIpv4(ip);
  if (networkAddr == null) return null;

  // Create subnet mask (e.g., /24 = 0xFFFFFF00)
  final mask =
      prefixLength == 0 ? 0 : (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;

  return _CidrRule(networkAddr, mask);
}

/// Parse IPv4 address string to 32-bit integer.
int? _parseIpv4(String ip) {
  final parts = ip.split('.');
  if (parts.length != 4) return null;

  int result = 0;
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return null;
    result = (result << 8) | octet;
  }
  return result;
}

/// Check if string is a valid IPv4 address.
bool _isValidIpv4(String ip) {
  return _parseIpv4(ip) != null;
}

/// Check if string is a valid IPv6 address.
/// Supports full form, compressed form (::), and mixed notation.
bool _isValidIpv6(String ip) {
  // Handle IPv4-mapped IPv6 (::ffff:192.168.1.1)
  if (ip.contains('.')) {
    // Could be IPv4-mapped, but for simplicity we'll just check for ::
    if (!ip.startsWith('::')) return false;
  }

  // Must contain at least one colon
  if (!ip.contains(':')) return false;

  // Can't have more than 7 colons (max 8 groups)
  if (ip.split(':').length > 8) return false;

  // Can't have more than one :: sequence
  if (ip.indexOf('::') != ip.lastIndexOf('::') && ip.contains('::')) {
    return false;
  }

  // Validate each group
  final parts = ip.split(':');
  for (final part in parts) {
    if (part.isEmpty) continue; // Empty parts are allowed with ::

    // Check for IPv4 embedded (last part might be IPv4)
    if (part.contains('.')) {
      if (_parseIpv4(part) == null) return false;
      continue;
    }

    // Each part should be 1-4 hex digits
    if (part.length > 4) return false;
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(part)) return false;
  }

  return true;
}

/// Check if IP matches any rule in the whitelist.
bool _isIpWhitelisted(String ip, List<_WhitelistRule> rules) {
  // Handle 'unknown' IP - never whitelisted unless wildcard
  if (ip == 'unknown') {
    return rules.any((r) => r.allowsAll);
  }

  for (final rule in rules) {
    if (rule.matches(ip)) {
      return true;
    }
  }
  return false;
}
