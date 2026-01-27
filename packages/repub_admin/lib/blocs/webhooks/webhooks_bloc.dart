import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/admin_api_client.dart';
import 'webhooks_event.dart';
import 'webhooks_state.dart';

class WebhooksBloc extends Bloc<WebhooksEvent, WebhooksState> {
  final AdminApiClient _apiClient;

  WebhooksBloc({AdminApiClient? apiClient})
      : _apiClient = apiClient ?? AdminApiClient(),
        super(const WebhooksInitial()) {
    on<LoadWebhooks>(_onLoadWebhooks);
    on<CreateWebhook>(_onCreateWebhook);
    on<UpdateWebhook>(_onUpdateWebhook);
    on<DeleteWebhook>(_onDeleteWebhook);
    on<TestWebhook>(_onTestWebhook);
    on<LoadWebhookDeliveries>(_onLoadDeliveries);
  }

  Future<void> _onLoadWebhooks(
    LoadWebhooks event,
    Emitter<WebhooksState> emit,
  ) async {
    emit(const WebhooksLoading());
    try {
      final webhooks = await _apiClient.listWebhooks(
        activeOnly: event.activeOnly,
      );
      emit(WebhooksLoaded(webhooks));
    } catch (e) {
      emit(WebhooksError(e.toString()));
    }
  }

  Future<void> _onCreateWebhook(
    CreateWebhook event,
    Emitter<WebhooksState> emit,
  ) async {
    emit(const WebhookCreating());
    try {
      final webhook = await _apiClient.createWebhook(
        url: event.url,
        events: event.events,
        secret: event.secret,
      );
      emit(WebhookCreated(webhook));
      // Reload the list
      add(const LoadWebhooks());
    } catch (e) {
      emit(WebhooksError(e.toString()));
    }
  }

  Future<void> _onUpdateWebhook(
    UpdateWebhook event,
    Emitter<WebhooksState> emit,
  ) async {
    emit(WebhookUpdating(event.id));
    try {
      final webhook = await _apiClient.updateWebhook(
        event.id,
        url: event.url,
        events: event.events,
        isActive: event.isActive,
      );
      emit(WebhookUpdated(webhook));
      // Reload the list
      add(const LoadWebhooks());
    } catch (e) {
      emit(WebhooksError(e.toString()));
    }
  }

  Future<void> _onDeleteWebhook(
    DeleteWebhook event,
    Emitter<WebhooksState> emit,
  ) async {
    emit(WebhookDeleting(event.id));
    try {
      await _apiClient.deleteWebhook(event.id);
      emit(WebhookDeleted(event.id));
      // Reload the list
      add(const LoadWebhooks());
    } catch (e) {
      emit(WebhooksError(e.toString()));
    }
  }

  Future<void> _onTestWebhook(
    TestWebhook event,
    Emitter<WebhooksState> emit,
  ) async {
    emit(WebhookTesting(event.id));
    try {
      final success = await _apiClient.testWebhook(event.id);
      emit(WebhookTestCompleted(webhookId: event.id, success: success));
      // Reload the list to show updated last_triggered_at
      add(const LoadWebhooks());
    } catch (e) {
      emit(WebhookTestCompleted(webhookId: event.id, success: false));
    }
  }

  Future<void> _onLoadDeliveries(
    LoadWebhookDeliveries event,
    Emitter<WebhooksState> emit,
  ) async {
    emit(WebhookDeliveriesLoading(event.webhookId));
    try {
      final deliveries = await _apiClient.getWebhookDeliveries(
        event.webhookId,
        limit: event.limit,
      );
      emit(WebhookDeliveriesLoaded(
        webhookId: event.webhookId,
        deliveries: deliveries,
      ));
    } catch (e) {
      emit(WebhooksError(e.toString()));
    }
  }
}
