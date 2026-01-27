import 'package:equatable/equatable.dart';

/// Represents an admin user in the system.
class AdminUserInfo extends Equatable {
  final String id;
  final String username;
  final DateTime createdAt;
  final DateTime? lastLoginAt;
  final int loginCount;

  const AdminUserInfo({
    required this.id,
    required this.username,
    required this.createdAt,
    this.lastLoginAt,
    required this.loginCount,
  });

  factory AdminUserInfo.fromJson(Map<String, dynamic> json) {
    return AdminUserInfo(
      id: json['id'] as String,
      username: json['username'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastLoginAt: json['last_login_at'] != null
          ? DateTime.parse(json['last_login_at'] as String)
          : null,
      loginCount: json['login_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'created_at': createdAt.toIso8601String(),
      'last_login_at': lastLoginAt?.toIso8601String(),
      'login_count': loginCount,
    };
  }

  @override
  List<Object?> get props => [id, username, createdAt, lastLoginAt, loginCount];
}

/// Represents a login attempt (successful or failed).
class LoginAttempt extends Equatable {
  final String id;
  final String adminUserId;
  final DateTime timestamp;
  final bool success;
  final String? ipAddress;
  final String? userAgent;
  final String? failureReason;

  const LoginAttempt({
    required this.id,
    required this.adminUserId,
    required this.timestamp,
    required this.success,
    this.ipAddress,
    this.userAgent,
    this.failureReason,
  });

  factory LoginAttempt.fromJson(Map<String, dynamic> json) {
    return LoginAttempt(
      id: json['id'] as String,
      adminUserId: json['admin_user_id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      success: json['success'] as bool,
      ipAddress: json['ip_address'] as String?,
      userAgent: json['user_agent'] as String?,
      failureReason: json['failure_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'admin_user_id': adminUserId,
      'timestamp': timestamp.toIso8601String(),
      'success': success,
      'ip_address': ipAddress,
      'user_agent': userAgent,
      'failure_reason': failureReason,
    };
  }

  bool get isSuspicious {
    // Flag suspicious activity
    if (!success && failureReason != null) {
      final suspicious = [
        'brute_force',
        'invalid_token',
        'multiple_failures',
      ];
      return suspicious.any(
        (pattern) => failureReason!.toLowerCase().contains(pattern),
      );
    }
    return false;
  }

  @override
  List<Object?> get props => [
        id,
        adminUserId,
        timestamp,
        success,
        ipAddress,
        userAgent,
        failureReason,
      ];
}
