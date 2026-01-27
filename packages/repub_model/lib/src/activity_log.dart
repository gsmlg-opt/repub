import 'dart:convert';

/// Activity log entry for tracking user and admin actions.
class ActivityLog {
  final String id;
  final DateTime timestamp;
  final String activityType; // 'package_published', 'user_registered', etc.
  final String actorType; // 'user', 'admin', 'system'
  final String? actorId; // user_id or admin_user_id
  final String? actorEmail;
  final String? actorUsername;
  final String? targetType; // 'package', 'user', 'config', etc.
  final String? targetId;
  final Map<String, dynamic>? metadata;
  final String? ipAddress;

  ActivityLog({
    required this.id,
    required this.timestamp,
    required this.activityType,
    required this.actorType,
    this.actorId,
    this.actorEmail,
    this.actorUsername,
    this.targetType,
    this.targetId,
    this.metadata,
    this.ipAddress,
  });

  /// Create from database row.
  factory ActivityLog.fromRow(Map<String, dynamic> row) {
    return ActivityLog(
      id: row['id'] as String,
      timestamp: row['timestamp'] as DateTime,
      activityType: row['activity_type'] as String,
      actorType: row['actor_type'] as String,
      actorId: row['actor_id'] as String?,
      actorEmail: row['actor_email'] as String?,
      actorUsername: row['actor_username'] as String?,
      targetType: row['target_type'] as String?,
      targetId: row['target_id'] as String?,
      metadata: row['metadata'] != null
          ? (row['metadata'] is String
              ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
              : row['metadata'] as Map<String, dynamic>)
          : null,
      ipAddress: row['ip_address'] as String?,
    );
  }

  /// Convert to JSON for API responses.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'activityType': activityType,
      'actorType': actorType,
      if (actorId != null) 'actorId': actorId,
      if (actorEmail != null) 'actorEmail': actorEmail,
      if (actorUsername != null) 'actorUsername': actorUsername,
      if (targetType != null) 'targetType': targetType,
      if (targetId != null) 'targetId': targetId,
      if (metadata != null) 'metadata': metadata,
      if (ipAddress != null) 'ipAddress': ipAddress,
    };
  }

  /// Human-readable description of the activity.
  String get description {
    switch (activityType) {
      case 'package_published':
        final version = metadata?['version'] as String?;
        return '$_actorName published $targetId ${version ?? ''}';
      case 'user_registered':
        return '$actorEmail registered';
      case 'admin_login':
        return '$actorUsername logged in to admin panel';
      case 'package_deleted':
        return '$_actorName deleted package $targetId';
      case 'package_version_deleted':
        final version = metadata?['version'] as String?;
        return '$_actorName deleted $targetId $version';
      case 'user_created':
        return '$_actorName created user $targetId';
      case 'user_deleted':
        return '$_actorName deleted user $targetId';
      case 'config_updated':
        return '$_actorName updated configuration';
      case 'cache_cleared':
        return '$_actorName cleared package cache';
      default:
        return '$activityType by $_actorName';
    }
  }

  String get _actorName {
    return actorUsername ?? actorEmail ?? 'Unknown';
  }
}
