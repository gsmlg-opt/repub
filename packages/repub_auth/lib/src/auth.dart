import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:repub_model/repub_model.dart';
import 'package:shelf/shelf.dart';

import 'auth_result.dart';

/// Token lookup function type.
typedef TokenLookup = Future<AuthToken?> Function(String tokenHash);

/// Token touch function type (update last used).
typedef TokenTouch = Future<void> Function(String tokenHash);

/// Authenticate a request from the Authorization header.
/// Returns AuthSuccess with the token if valid, or an error result.
/// Permissions are checked by the handlers based on package ownership.
Future<AuthResult> authenticate(
  Request request, {
  required TokenLookup lookupToken,
  required TokenTouch touchToken,
}) async {
  final authHeader = request.headers['authorization'];

  if (authHeader == null || authHeader.isEmpty) {
    return AuthMissing();
  }

  // Parse "Bearer <token>"
  final parts = authHeader.split(' ');
  if (parts.length != 2 || parts[0].toLowerCase() != 'bearer') {
    return AuthInvalid('Invalid authorization header format');
  }

  final token = parts[1];
  final tokenHash = sha256.convert(utf8.encode(token)).toString();

  // Look up token
  final authToken = await lookupToken(tokenHash);
  if (authToken == null) {
    return AuthInvalid('Invalid token');
  }

  // Check if token is expired
  if (authToken.isExpired) {
    return AuthInvalid('Token has expired');
  }

  // Update last used
  await touchToken(tokenHash);

  return AuthSuccess(authToken);
}

/// Create a 401 Unauthorized response with WWW-Authenticate header.
Response unauthorized(String message) {
  return Response(
    401,
    headers: {
      'content-type': 'application/json',
      'www-authenticate': 'Bearer realm="pub", message="$message"',
    },
    body: jsonEncode({
      'error': {'code': 'unauthorized', 'message': message},
    }),
  );
}

/// Create a 403 Forbidden response.
Response forbidden(String message) {
  return Response(
    403,
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'error': {'code': 'forbidden', 'message': message},
    }),
  );
}

/// Get the authenticated token from request context.
AuthToken? getAuthToken(Request request) {
  return request.context['auth_token'] as AuthToken?;
}

/// Get the authenticated user ID from request context.
/// Returns anonymous user ID if not authenticated.
String getAuthUserId(Request request) {
  final token = getAuthToken(request);
  return token?.userId ?? User.anonymousId;
}
