import 'package:repub_model/repub_model.dart';
import 'package:shelf/shelf.dart';

/// Check if a token has a specific scope.
///
/// Returns true if the token has the exact scope specified.
/// Does not check admin scope - use [hasAdminScope] for that.
bool hasScope(AuthToken token, String scope) {
  return token.scopes.contains(scope);
}

/// Check if a token has admin scope.
///
/// Admin scope grants full access to all operations.
bool hasAdminScope(AuthToken token) {
  return token.scopes.contains('admin');
}

/// Check if a token can publish all packages.
///
/// Returns true if token has 'admin' or 'publish:all' scope.
bool canPublishAll(AuthToken token) {
  return hasAdminScope(token) || hasScope(token, 'publish:all');
}

/// Check if a token can publish a specific package.
///
/// Returns true if token has:
/// - 'admin' scope
/// - 'publish:all' scope
/// - 'publish:pkg:`<packageName>`' scope
bool canPublishPackage(AuthToken token, String packageName) {
  return hasAdminScope(token) ||
      hasScope(token, 'publish:all') ||
      hasScope(token, 'publish:pkg:$packageName');
}

/// Check if a token has read access.
///
/// Returns true if token has 'admin' or 'read:all' scope.
/// Only relevant when download authentication is required.
bool canRead(AuthToken token) {
  return hasAdminScope(token) || hasScope(token, 'read:all');
}

/// Require a specific scope or return 403 Forbidden response.
///
/// If the token has the required scope, returns null (success).
/// If the token does NOT have the scope, returns a 403 Response.
///
/// Example:
/// ```dart
/// final forbidden = requireScope(token, 'admin');
/// if (forbidden != null) return forbidden;
/// // Continue with admin operation...
/// ```
Response? requireScope(AuthToken token, String scope) {
  if (hasScope(token, scope)) return null;

  return Response.forbidden(
    'Insufficient permissions: requires scope "$scope"',
    headers: {'content-type': 'text/plain'},
  );
}

/// Require admin scope or return 403 Forbidden response.
///
/// If the token has admin scope, returns null (success).
/// If the token does NOT have admin scope, returns a 403 Response.
///
/// Example:
/// ```dart
/// final forbidden = requireAdminScope(token);
/// if (forbidden != null) return forbidden;
/// // Continue with admin operation...
/// ```
Response? requireAdminScope(AuthToken token) {
  if (hasAdminScope(token)) return null;

  return Response.forbidden(
    'Insufficient permissions: requires admin scope',
    headers: {'content-type': 'text/plain'},
  );
}

/// Require package publish permission or return 403 Forbidden response.
///
/// If the token can publish the specified package, returns null (success).
/// If the token cannot publish, returns a 403 Response.
///
/// Example:
/// ```dart
/// final forbidden = requirePackagePublishScope(token, 'my_package');
/// if (forbidden != null) return forbidden;
/// // Continue with publish operation...
/// ```
Response? requirePackagePublishScope(AuthToken token, String packageName) {
  if (canPublishPackage(token, packageName)) return null;

  return Response.forbidden(
    'Insufficient permissions: cannot publish package "$packageName"',
    headers: {'content-type': 'text/plain'},
  );
}

/// Require read permission or return 403 Forbidden response.
///
/// If the token has read access, returns null (success).
/// If the token does NOT have read access, returns a 403 Response.
///
/// Only relevant when download authentication is required.
///
/// Example:
/// ```dart
/// final forbidden = requireReadScope(token);
/// if (forbidden != null) return forbidden;
/// // Continue with download operation...
/// ```
Response? requireReadScope(AuthToken token) {
  if (canRead(token)) return null;

  return Response.forbidden(
    'Insufficient permissions: requires read:all scope',
    headers: {'content-type': 'text/plain'},
  );
}
