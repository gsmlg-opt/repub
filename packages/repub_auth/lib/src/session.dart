import 'dart:convert';

import 'package:repub_model/repub_model.dart';
import 'package:shelf/shelf.dart';

/// Session lookup function type.
typedef SessionLookup = Future<UserSession?> Function(String sessionId);

/// Session result types.
sealed class SessionResult {}

class SessionValid extends SessionResult {
  final UserSession session;
  SessionValid(this.session);
}

class SessionMissing extends SessionResult {}

class SessionInvalid extends SessionResult {
  final String message;
  SessionInvalid(this.message);
}

class SessionExpired extends SessionResult {}

/// Cookie name for session ID.
const sessionCookieName = 'repub_session';

/// Get session from request cookie.
/// Returns SessionValid with session if valid, or an error result.
Future<SessionResult> getSession(
  Request request, {
  required SessionLookup lookupSession,
}) async {
  final cookieHeader = request.headers['cookie'];
  if (cookieHeader == null || cookieHeader.isEmpty) {
    return SessionMissing();
  }

  // Parse cookies
  final cookies = _parseCookies(cookieHeader);
  final sessionId = cookies[sessionCookieName];

  if (sessionId == null || sessionId.isEmpty) {
    return SessionMissing();
  }

  // Look up session
  final session = await lookupSession(sessionId);
  if (session == null) {
    return SessionInvalid('Session not found');
  }

  // Check if expired
  if (session.isExpired) {
    return SessionExpired();
  }

  return SessionValid(session);
}

/// Create a Set-Cookie header value for a session.
String createSessionCookie(String sessionId,
    {Duration? maxAge, bool secure = false}) {
  final parts = <String>[
    '$sessionCookieName=$sessionId',
    'Path=/',
    'HttpOnly',
    'SameSite=Lax',
  ];

  if (maxAge != null) {
    parts.add('Max-Age=${maxAge.inSeconds}');
  }

  if (secure) {
    parts.add('Secure');
  }

  return parts.join('; ');
}

/// Create a Set-Cookie header to clear the session.
String clearSessionCookie({bool secure = false}) {
  final parts = <String>[
    '$sessionCookieName=',
    'Path=/',
    'HttpOnly',
    'SameSite=Lax',
    'Max-Age=0',
  ];

  if (secure) {
    parts.add('Secure');
  }

  return parts.join('; ');
}

/// Get user ID from session in request context.
/// Returns null if no valid session.
String? getSessionUserId(Request request) {
  final session = request.context['session'] as UserSession?;
  return session?.userId;
}

/// Create a JSON error response for session errors.
Response sessionErrorResponse(SessionResult result) {
  switch (result) {
    case SessionMissing():
      return Response(
        401,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {'code': 'session_required', 'message': 'Login required'},
        }),
      );
    case SessionInvalid(:final message):
      return Response(
        401,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {'code': 'session_invalid', 'message': message},
        }),
      );
    case SessionExpired():
      return Response(
        401,
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'error': {
            'code': 'session_expired',
            'message': 'Session has expired'
          },
        }),
      );
    case SessionValid():
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
