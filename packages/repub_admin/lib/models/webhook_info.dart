import 'package:equatable/equatable.dart';

/// Information about a webhook configuration.
class WebhookInfo extends Equatable {
  final String id;
  final String url;
  final List<String> events;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastTriggeredAt;
  final int failureCount;

  const WebhookInfo({
    required this.id,
    required this.url,
    required this.events,
    required this.isActive,
    required this.createdAt,
    this.lastTriggeredAt,
    this.failureCount = 0,
  });

  factory WebhookInfo.fromJson(Map<String, dynamic> json) {
    return WebhookInfo(
      id: json['id'] as String,
      url: json['url'] as String,
      events: (json['events'] as List<dynamic>).cast<String>(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastTriggeredAt: json['last_triggered_at'] != null
          ? DateTime.parse(json['last_triggered_at'] as String)
          : null,
      failureCount: json['failure_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'events': events,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        if (lastTriggeredAt != null)
          'last_triggered_at': lastTriggeredAt!.toIso8601String(),
        'failure_count': failureCount,
      };

  WebhookInfo copyWith({
    String? url,
    List<String>? events,
    bool? isActive,
    DateTime? lastTriggeredAt,
    int? failureCount,
  }) {
    return WebhookInfo(
      id: id,
      url: url ?? this.url,
      events: events ?? this.events,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
      failureCount: failureCount ?? this.failureCount,
    );
  }

  @override
  List<Object?> get props => [
        id,
        url,
        events,
        isActive,
        createdAt,
        lastTriggeredAt,
        failureCount,
      ];
}

/// Webhook delivery log entry.
class WebhookDeliveryInfo extends Equatable {
  final String id;
  final String webhookId;
  final String eventType;
  final int statusCode;
  final bool success;
  final String? error;
  final int durationMs;
  final DateTime deliveredAt;

  const WebhookDeliveryInfo({
    required this.id,
    required this.webhookId,
    required this.eventType,
    required this.statusCode,
    required this.success,
    this.error,
    required this.durationMs,
    required this.deliveredAt,
  });

  factory WebhookDeliveryInfo.fromJson(Map<String, dynamic> json) {
    return WebhookDeliveryInfo(
      id: json['id'] as String,
      webhookId: json['webhook_id'] as String,
      eventType: json['event_type'] as String,
      statusCode: json['status_code'] as int,
      success: json['success'] as bool,
      error: json['error'] as String?,
      durationMs: json['duration_ms'] as int,
      deliveredAt: DateTime.parse(json['delivered_at'] as String),
    );
  }

  @override
  List<Object?> get props => [
        id,
        webhookId,
        eventType,
        statusCode,
        success,
        error,
        durationMs,
        deliveredAt,
      ];
}

/// Supported webhook event types.
class WebhookEventTypes {
  static const packagePublished = 'package.published';
  static const packageDeleted = 'package.deleted';
  static const versionDeleted = 'version.deleted';
  static const packageDiscontinued = 'package.discontinued';
  static const packageReactivated = 'package.reactivated';
  static const userRegistered = 'user.registered';
  static const cacheCleared = 'cache.cleared';
  static const wildcard = '*';

  static const all = [
    packagePublished,
    packageDeleted,
    versionDeleted,
    packageDiscontinued,
    packageReactivated,
    userRegistered,
    cacheCleared,
  ];

  static String displayName(String eventType) {
    switch (eventType) {
      case wildcard:
        return 'All Events';
      case packagePublished:
        return 'Package Published';
      case packageDeleted:
        return 'Package Deleted';
      case versionDeleted:
        return 'Version Deleted';
      case packageDiscontinued:
        return 'Package Discontinued';
      case packageReactivated:
        return 'Package Reactivated';
      case userRegistered:
        return 'User Registered';
      case cacheCleared:
        return 'Cache Cleared';
      default:
        return eventType;
    }
  }
}
