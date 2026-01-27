/// Webhook configuration for event notifications.
///
/// Webhooks allow external services to be notified when events occur
/// in the package registry, such as package publishes, deletions, etc.
class Webhook {
  final String id;
  final String url;
  final String? secret;
  final List<String> events;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastTriggeredAt;
  final int failureCount;

  const Webhook({
    required this.id,
    required this.url,
    this.secret,
    required this.events,
    this.isActive = true,
    required this.createdAt,
    this.lastTriggeredAt,
    this.failureCount = 0,
  });

  /// Check if this webhook should be triggered for a given event type.
  bool shouldTrigger(String eventType) {
    if (!isActive) return false;
    return events.contains('*') || events.contains(eventType);
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

  factory Webhook.fromJson(Map<String, dynamic> json) => Webhook(
        id: json['id'] as String,
        url: json['url'] as String,
        secret: json['secret'] as String?,
        events: (json['events'] as List).cast<String>(),
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        lastTriggeredAt: json['last_triggered_at'] != null
            ? DateTime.parse(json['last_triggered_at'] as String)
            : null,
        failureCount: json['failure_count'] as int? ?? 0,
      );

  Webhook copyWith({
    String? url,
    String? secret,
    List<String>? events,
    bool? isActive,
    DateTime? lastTriggeredAt,
    int? failureCount,
  }) =>
      Webhook(
        id: id,
        url: url ?? this.url,
        secret: secret ?? this.secret,
        events: events ?? this.events,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        lastTriggeredAt: lastTriggeredAt ?? this.lastTriggeredAt,
        failureCount: failureCount ?? this.failureCount,
      );
}

/// Supported webhook event types.
class WebhookEventType {
  /// Package published (new version).
  static const packagePublished = 'package.published';

  /// Package deleted.
  static const packageDeleted = 'package.deleted';

  /// Package version deleted.
  static const versionDeleted = 'version.deleted';

  /// Package discontinued.
  static const packageDiscontinued = 'package.discontinued';

  /// Package reactivated (undiscontinued).
  static const packageReactivated = 'package.reactivated';

  /// User registered.
  static const userRegistered = 'user.registered';

  /// Cached package cleared.
  static const cacheCleared = 'cache.cleared';

  /// All supported event types.
  static const all = [
    packagePublished,
    packageDeleted,
    versionDeleted,
    packageDiscontinued,
    packageReactivated,
    userRegistered,
    cacheCleared,
  ];

  /// Check if an event type is valid.
  static bool isValid(String eventType) {
    return eventType == '*' || all.contains(eventType);
  }
}

/// Webhook delivery payload.
class WebhookPayload {
  final String eventType;
  final DateTime timestamp;
  final Map<String, dynamic> data;

  const WebhookPayload({
    required this.eventType,
    required this.timestamp,
    required this.data,
  });

  Map<String, dynamic> toJson() => {
        'event': eventType,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'data': data,
      };
}

/// Result of a webhook delivery attempt.
class WebhookDeliveryResult {
  final bool success;
  final int statusCode;
  final String? error;
  final Duration duration;

  const WebhookDeliveryResult({
    required this.success,
    required this.statusCode,
    this.error,
    required this.duration,
  });
}

/// Webhook delivery log entry.
class WebhookDelivery {
  final String id;
  final String webhookId;
  final String eventType;
  final Map<String, dynamic> payload;
  final int statusCode;
  final bool success;
  final String? error;
  final Duration duration;
  final DateTime deliveredAt;

  const WebhookDelivery({
    required this.id,
    required this.webhookId,
    required this.eventType,
    required this.payload,
    required this.statusCode,
    required this.success,
    this.error,
    required this.duration,
    required this.deliveredAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'webhook_id': webhookId,
        'event_type': eventType,
        'payload': payload,
        'status_code': statusCode,
        'success': success,
        if (error != null) 'error': error,
        'duration_ms': duration.inMilliseconds,
        'delivered_at': deliveredAt.toIso8601String(),
      };
}
