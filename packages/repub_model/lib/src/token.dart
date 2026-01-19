/// Authentication token for API access.
class AuthToken {
  final String tokenHash;
  final String label;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  const AuthToken({
    required this.tokenHash,
    required this.label,
    required this.scopes,
    required this.createdAt,
    this.lastUsedAt,
  });

  /// Check if this token has the required scope.
  bool hasScope(String requiredScope) {
    // Admin scope grants all permissions
    if (scopes.contains('admin')) return true;

    // Direct match
    if (scopes.contains(requiredScope)) return true;

    // Check for wildcard scopes
    // e.g., 'publish:all' grants 'publish:pkg:foo'
    if (requiredScope.startsWith('publish:pkg:') &&
        scopes.contains('publish:all')) {
      return true;
    }

    // read:all grants any read
    if (requiredScope.startsWith('read:') && scopes.contains('read:all')) {
      return true;
    }

    return false;
  }

  /// Check if token can publish a specific package.
  bool canPublish(String packageName) {
    return hasScope('publish:all') || hasScope('publish:pkg:$packageName');
  }

  /// Check if token can read/download packages.
  bool canRead() {
    return hasScope('read:all');
  }
}

/// Available token scopes.
class TokenScopes {
  static const admin = 'admin';
  static const publishAll = 'publish:all';
  static const readAll = 'read:all';

  static String publishPackage(String name) => 'publish:pkg:$name';

  /// Valid scope patterns.
  static bool isValid(String scope) {
    if (scope == admin || scope == publishAll || scope == readAll) {
      return true;
    }
    if (scope.startsWith('publish:pkg:') && scope.length > 12) {
      return true;
    }
    return false;
  }
}
