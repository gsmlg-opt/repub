/// An admin user account in the registry.
/// Admin users are managed via CLI only and have access to admin endpoints.
class AdminUser {
  final String id;
  final String username;
  final String? passwordHash;
  final String? name;
  final bool isActive;
  final bool mustChangePassword;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  const AdminUser({
    required this.id,
    required this.username,
    this.passwordHash,
    this.name,
    this.isActive = true,
    this.mustChangePassword = false,
    required this.createdAt,
    this.lastLoginAt,
  });

  /// Convert to JSON for API response (excludes password hash).
  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'name': name,
        'isActive': isActive,
        'mustChangePassword': mustChangePassword,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (lastLoginAt != null)
          'lastLoginAt': lastLoginAt!.toUtc().toIso8601String(),
      };

  /// Create from JSON (for API responses, no password hash).
  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as String,
        username: json['username'] as String,
        name: json['name'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        mustChangePassword: json['mustChangePassword'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastLoginAt: json['lastLoginAt'] != null
            ? DateTime.parse(json['lastLoginAt'] as String)
            : null,
      );
}
