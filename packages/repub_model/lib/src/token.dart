/// Authentication token for API access.
/// Tokens authenticate users - permissions are determined by scopes.
///
/// Supported scopes:
/// - `admin`: Full access including admin panel
/// - `publish:all`: Publish any package
/// - `publish:pkg:<name>`: Publish specific package only
/// - `read:all`: Read/download (when download auth required)
class AuthToken {
  final String tokenHash;
  final String userId;
  final String label;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;

  const AuthToken({
    required this.tokenHash,
    required this.userId,
    required this.label,
    required this.scopes,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  /// Check if token is expired.
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Check if token has a specific scope.
  bool hasScope(String scope) => scopes.contains(scope);

  /// Check if token has admin scope.
  bool get isAdmin => hasScope('admin');

  /// Check if token can publish all packages.
  bool get canPublishAll => isAdmin || hasScope('publish:all');

  /// Check if token can publish a specific package.
  bool canPublish(String packageName) {
    return canPublishAll || hasScope('publish:pkg:$packageName');
  }

  /// Check if token has read access (for download auth).
  bool get canRead => isAdmin || hasScope('read:all');

  /// Convert to JSON for API response (excludes token hash).
  Map<String, dynamic> toJson() => {
        'label': label,
        'scopes': scopes,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (lastUsedAt != null)
          'lastUsedAt': lastUsedAt!.toUtc().toIso8601String(),
        if (expiresAt != null)
          'expiresAt': expiresAt!.toUtc().toIso8601String(),
      };
}
