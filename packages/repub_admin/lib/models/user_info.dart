import 'package:equatable/equatable.dart';

/// Represents a regular user in the system.
class UserInfo extends Equatable {
  final String id;
  final String email;
  final DateTime createdAt;
  final bool isActive;
  final int tokenCount;
  final DateTime? lastLoginAt;

  const UserInfo({
    required this.id,
    required this.email,
    required this.createdAt,
    required this.isActive,
    required this.tokenCount,
    this.lastLoginAt,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id'] as String,
      email: json['email'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      isActive: json['is_active'] as bool? ?? true,
      tokenCount: json['token_count'] as int? ?? 0,
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
      'token_count': tokenCount,
      'last_login_at': lastLoginAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
        id,
        email,
        createdAt,
        isActive,
        tokenCount,
        lastLoginAt,
      ];
}

/// Represents an API token for a user.
class TokenInfo extends Equatable {
  final String label;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;

  const TokenInfo({
    required this.label,
    required this.scopes,
    required this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  factory TokenInfo.fromJson(Map<String, dynamic> json) {
    return TokenInfo(
      label: json['label'] as String,
      scopes: (json['scopes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'] as String)
          : null,
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'scopes': scopes,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'expiresAt': expiresAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [label, scopes, createdAt, lastUsedAt, expiresAt];
}
