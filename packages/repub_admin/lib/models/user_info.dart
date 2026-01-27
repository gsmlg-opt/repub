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
  final String id;
  final String name;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime? expiresAt;

  const TokenInfo({
    required this.id,
    required this.name,
    required this.scopes,
    required this.createdAt,
    this.expiresAt,
  });

  factory TokenInfo.fromJson(Map<String, dynamic> json) {
    return TokenInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      scopes: (json['scopes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'scopes': scopes,
      'created_at': createdAt.toIso8601String(),
      'expires_at': expiresAt?.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [id, name, scopes, createdAt, expiresAt];
}
