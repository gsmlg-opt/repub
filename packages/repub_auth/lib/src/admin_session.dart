import 'dart:convert';

import 'package:repub_model/repub_model.dart';
import 'package:shelf/shelf.dart';

/// Session lookup function type for admin sessions.
typedef AdminSessionLookup = Future<UserSession?> Function(String sessionId);

/// Admin session result types.
sealed class AdminSessionResult {}

class AdminSessionValid extends AdminSessionResult {
  final UserSession session;
  AdminSessionValid(this.session);
}

class AdminSessionMissing extends AdminSessionResult {}

class AdminSessionInvalid extends AdminSessionResult {
  final String message;
  AdminSessionInvalid(this.message);
}

class AdminSessionExpired extends AdminSessionResult {}

/// Cookie name for admin session ID.
const adminSessionCookieName = 'admin_session';

/// Get admin session from request cookie.
/// Returns AdminSessionValid with session if valid, or an error result.
Future<AdminSessionResult> getAdminSession(
  Request request, {
  required AdminSessionLookup lookupSession,
}) async {
  final cookieHeader = request.headers['cookie'];
  if (cookieHeader == null || cookieHeader.isEmpty) {
    return AdminSessionMissing();
  }

  // Parse cookies
  final cookies = _parseCookies(cookieHeader);
  final sessionId = cookies[adminSessionCookieName];

  if (sessionId == null || sessionId.isEmpty) {
    return AdminSessionMissing();
  }

  // Look up session
  final session = await lookupSession(sessionId);
  if (session == null) {
    return AdminSessionInvalid('Admin session not found');
  }

  // Check if this is actually an admin session
  if (!session.isAdmin) {
    return AdminSessionInvalid('Not an admin session');
  }

  // Check if expired
  if (session.isExpired) {
    return AdminSessionExpired();
  }

  return AdminSessionValid(session);
}

/// Create a Set-Cookie header value for an admin session.
/// Admin sessions use stricter settings than regular user sessions.
String createAdminSessionCookie(String sessionId,
    {Duration? maxAge, bool secure = false}) {
  final parts = <String>[
    '$adminSessionCookieName=$sessionId',
    'Path=/admin',
    'HttpOnly',
    'SameSite=Strict',
  ];

  if (maxAge != null) {
    parts.add('Max-Age=${maxAge.inSeconds}');
  }

  if (secure) {
    parts.add('Secure');
  }

  return parts.join('; ');
}

/// Create a Set-Cookie header to clear the admin session.
String clearAdminSessionCookie({bool secure = false}) {
  final parts = <String>[
    '$adminSessionCookieName=',
    'Path=/admin',
    'HttpOnly',
    'SameSite=Strict',
    'Max-Age=0',
  ];

  if (secure) {
    parts.add('Secure');
  }

  return parts.join('; ');
}

/// Get admin user ID from admin session in request context.
/// Returns null if no valid admin session.
String? getAdminSessionUserId(Request request) {
  final session = request.context['adminSession'] as UserSession?;
  return session?.userId;
}

/// Create a JSON error response for admin session errors.
Response adminSessionErrorResponse(AdminSessionResult result) {
  switch (result) {
    case AdminSessionMissing():
      return Response(
        401,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {
            'code': 'admin_login_required',
            'message': 'Admin login required'
          },
        }),
      );
    case AdminSessionInvalid(:final message):
      return Response(
        401,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {'code': 'admin_session_invalid', 'message': message},
        }),
      );
    case AdminSessionExpired():
      return Response(
        401,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {
            'code': 'admin_session_expired',
            'message': 'Admin session has expired'
          },
        }),
      );
    case AdminSessionValid():
      throw StateError('Should not reach here');
  }
}

/// Parse a Cookie header into a map of name -> value.
Map<String, String> _parseCookies(String cookieHeader) {
  final cookies = <String, String>{};
  for (final part in cookieHeader.split(';')) {
    final trimmed = part.trim();
    final eqIndex = trimmed.indexOf('=');
    if (eqIndex > 0) {
      final name = trimmed.substring(0, eqIndex).trim();
      final value = trimmed.substring(eqIndex + 1).trim();
      cookies[name] = value;
    }
  }
  return cookies;
}
