/// Authentication token for API access.
/// Tokens authenticate users - permissions are determined by package ownership.
class AuthToken {
  final String tokenHash;
  final String userId;
  final String label;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;

  const AuthToken({
    required this.tokenHash,
    required this.userId,
    required this.label,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  /// Check if token is expired.
  bool get isExpired => expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Convert to JSON for API response (excludes token hash).
  Map<String, dynamic> toJson() => {
        'label': label,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (lastUsedAt != null)
          'lastUsedAt': lastUsedAt!.toUtc().toIso8601String(),
        if (expiresAt != null)
          'expiresAt': expiresAt!.toUtc().toIso8601String(),
      };
}
