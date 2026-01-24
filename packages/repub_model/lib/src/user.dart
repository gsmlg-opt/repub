/// A user account in the registry.
class User {
  /// Anonymous user ID - used for unauthenticated actions.
  static const anonymousId = '00000000-0000-0000-0000-000000000000';

  final String id;
  final String email;
  final String? passwordHash;
  final String? name;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  const User({
    required this.id,
    required this.email,
    this.passwordHash,
    this.name,
    this.isActive = true,
    required this.createdAt,
    this.lastLoginAt,
  });

  /// Check if this is the anonymous user.
  bool get isAnonymous => id == anonymousId;

  /// Create the anonymous user instance.
  factory User.anonymous() => User(
        id: anonymousId,
        email: 'anonymous@localhost',
        name: 'Anonymous',
        isActive: true,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Convert to JSON for API response (excludes sensitive fields).
  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'isActive': isActive,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (lastLoginAt != null)
          'lastLoginAt': lastLoginAt!.toUtc().toIso8601String(),
      };

  /// Create from JSON (for API responses, no password hash).
  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        email: json['email'] as String,
        name: json['name'] as String?,
        isActive: json['isActive'] as bool? ?? true,
        createdAt: DateTime.parse(json['createdAt'] as String),
        lastLoginAt: json['lastLoginAt'] != null
            ? DateTime.parse(json['lastLoginAt'] as String)
            : null,
      );
}

/// Session type discriminator for user sessions.
enum SessionType {
  user,
  admin;

  String get value => name;

  static SessionType fromString(String value) {
    return SessionType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => SessionType.user,
    );
  }
}

/// User session for web authentication.
class UserSession {
  final String sessionId;
  final String userId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final SessionType type;

  const UserSession({
    required this.sessionId,
    required this.userId,
    required this.createdAt,
    required this.expiresAt,
    this.type = SessionType.user,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isAdmin => type == SessionType.admin;
}
