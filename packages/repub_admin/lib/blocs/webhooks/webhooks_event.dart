import 'package:equatable/equatable.dart';

abstract class WebhooksEvent extends Equatable {
  const WebhooksEvent();

  @override
  List<Object?> get props => [];
}

/// Load all webhooks.
class LoadWebhooks extends WebhooksEvent {
  final bool activeOnly;

  const LoadWebhooks({this.activeOnly = false});

  @override
  List<Object?> get props => [activeOnly];
}

/// Create a new webhook.
class CreateWebhook extends WebhooksEvent {
  final String url;
  final List<String> events;
  final String? secret;

  const CreateWebhook({
    required this.url,
    required this.events,
    this.secret,
  });

  @override
  List<Object?> get props => [url, events, secret];
}

/// Update an existing webhook.
class UpdateWebhook extends WebhooksEvent {
  final String id;
  final String? url;
  final List<String>? events;
  final bool? isActive;

  const UpdateWebhook({
    required this.id,
    this.url,
    this.events,
    this.isActive,
  });

  @override
  List<Object?> get props => [id, url, events, isActive];
}

/// Delete a webhook.
class DeleteWebhook extends WebhooksEvent {
  final String id;

  const DeleteWebhook(this.id);

  @override
  List<Object?> get props => [id];
}

/// Test a webhook.
class TestWebhook extends WebhooksEvent {
  final String id;

  const TestWebhook(this.id);

  @override
  List<Object?> get props => [id];
}

/// Load deliveries for a webhook.
class LoadWebhookDeliveries extends WebhooksEvent {
  final String webhookId;
  final int limit;

  const LoadWebhookDeliveries({
    required this.webhookId,
    this.limit = 50,
  });

  @override
  List<Object?> get props => [webhookId, limit];
}
