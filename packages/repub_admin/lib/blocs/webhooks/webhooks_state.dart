import 'package:equatable/equatable.dart';
import '../../models/webhook_info.dart';

abstract class WebhooksState extends Equatable {
  const WebhooksState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class WebhooksInitial extends WebhooksState {
  const WebhooksInitial();
}

/// Loading webhooks list.
class WebhooksLoading extends WebhooksState {
  const WebhooksLoading();
}

/// Webhooks loaded successfully.
class WebhooksLoaded extends WebhooksState {
  final List<WebhookInfo> webhooks;

  const WebhooksLoaded(this.webhooks);

  @override
  List<Object?> get props => [webhooks];
}

/// Error loading webhooks.
class WebhooksError extends WebhooksState {
  final String message;

  const WebhooksError(this.message);

  @override
  List<Object?> get props => [message];
}

/// Creating a new webhook.
class WebhookCreating extends WebhooksState {
  const WebhookCreating();
}

/// Webhook created successfully.
class WebhookCreated extends WebhooksState {
  final WebhookInfo webhook;

  const WebhookCreated(this.webhook);

  @override
  List<Object?> get props => [webhook];
}

/// Updating a webhook.
class WebhookUpdating extends WebhooksState {
  final String webhookId;

  const WebhookUpdating(this.webhookId);

  @override
  List<Object?> get props => [webhookId];
}

/// Webhook updated successfully.
class WebhookUpdated extends WebhooksState {
  final WebhookInfo webhook;

  const WebhookUpdated(this.webhook);

  @override
  List<Object?> get props => [webhook];
}

/// Deleting a webhook.
class WebhookDeleting extends WebhooksState {
  final String webhookId;

  const WebhookDeleting(this.webhookId);

  @override
  List<Object?> get props => [webhookId];
}

/// Webhook deleted successfully.
class WebhookDeleted extends WebhooksState {
  final String webhookId;

  const WebhookDeleted(this.webhookId);

  @override
  List<Object?> get props => [webhookId];
}

/// Testing a webhook.
class WebhookTesting extends WebhooksState {
  final String webhookId;

  const WebhookTesting(this.webhookId);

  @override
  List<Object?> get props => [webhookId];
}

/// Webhook test completed.
class WebhookTestCompleted extends WebhooksState {
  final String webhookId;
  final bool success;

  const WebhookTestCompleted({
    required this.webhookId,
    required this.success,
  });

  @override
  List<Object?> get props => [webhookId, success];
}

/// Loading webhook deliveries.
class WebhookDeliveriesLoading extends WebhooksState {
  final String webhookId;

  const WebhookDeliveriesLoading(this.webhookId);

  @override
  List<Object?> get props => [webhookId];
}

/// Webhook deliveries loaded.
class WebhookDeliveriesLoaded extends WebhooksState {
  final String webhookId;
  final List<WebhookDeliveryInfo> deliveries;

  const WebhookDeliveriesLoaded({
    required this.webhookId,
    required this.deliveries,
  });

  @override
  List<Object?> get props => [webhookId, deliveries];
}
