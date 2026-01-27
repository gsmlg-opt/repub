import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../blocs/webhooks/webhooks_bloc.dart';
import '../blocs/webhooks/webhooks_event.dart';
import '../blocs/webhooks/webhooks_state.dart';
import '../models/webhook_info.dart';
import '../widgets/admin_layout.dart';

class WebhooksScreen extends StatefulWidget {
  const WebhooksScreen({super.key});

  @override
  State<WebhooksScreen> createState() => _WebhooksScreenState();
}

class _WebhooksScreenState extends State<WebhooksScreen> {
  @override
  void initState() {
    super.initState();
    context.read<WebhooksBloc>().add(const LoadWebhooks());
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/webhooks',
      child: BlocConsumer<WebhooksBloc, WebhooksState>(
        listener: (context, state) {
          if (state is WebhookCreated) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Webhook created successfully')),
            );
          } else if (state is WebhookDeleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Webhook deleted')),
            );
          } else if (state is WebhookTestCompleted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.success
                    ? 'Test webhook sent successfully'
                    : 'Test webhook failed'),
                backgroundColor: state.success ? Colors.green : Colors.red,
              ),
            );
          } else if (state is WebhooksError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: ${state.message}'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
        builder: (context, state) {
          return Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 16),
                  _buildInfoBanner(context),
                  const SizedBox(height: 16),
                  Expanded(child: _buildContent(context, state)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.webhook, size: 32),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Webhooks',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Text(
                'Manage webhooks for event notifications',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _showCreateDialog(context),
          icon: const Icon(Icons.add),
          label: const Text('Add Webhook'),
        ),
      ],
    );
  }

  Widget _buildInfoBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Webhook Events',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Webhooks notify external services when events occur: '
                  'package.published, package.deleted, user.registered, and more. '
                  'Use "*" to subscribe to all events.',
                  style: TextStyle(color: Colors.blue.shade800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, WebhooksState state) {
    if (state is WebhooksLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is WebhooksLoaded) {
      if (state.webhooks.isEmpty) {
        return _buildEmptyState(context);
      }
      return _buildWebhooksList(context, state.webhooks);
    }

    if (state is WebhooksError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text('Error: ${state.message}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  context.read<WebhooksBloc>().add(const LoadWebhooks()),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.webhook, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No webhooks configured',
            style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add a webhook to receive notifications about package events',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showCreateDialog(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Your First Webhook'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebhooksList(BuildContext context, List<WebhookInfo> webhooks) {
    return Card(
      child: ListView.separated(
        itemCount: webhooks.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final webhook = webhooks[index];
          return _buildWebhookTile(context, webhook);
        },
      ),
    );
  }

  Widget _buildWebhookTile(BuildContext context, WebhookInfo webhook) {
    final dateFormat = DateFormat('MMM d, y HH:mm');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor:
            webhook.isActive ? Colors.green.shade100 : Colors.grey.shade200,
        child: Icon(
          Icons.webhook,
          color: webhook.isActive ? Colors.green : Colors.grey,
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              webhook.url,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          if (!webhook.isActive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Disabled',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          if (webhook.failureCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${webhook.failureCount} failures',
                style: TextStyle(fontSize: 12, color: Colors.red.shade700),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: webhook.events.map((event) {
              return Chip(
                label: Text(
                  WebhookEventTypes.displayName(event),
                  style: const TextStyle(fontSize: 11),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Created ${dateFormat.format(webhook.createdAt.toLocal())}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (webhook.lastTriggeredAt != null) ...[
                const Text(' • ', style: TextStyle(color: Colors.grey)),
                Text(
                  'Last triggered ${dateFormat.format(webhook.lastTriggeredAt!.toLocal())}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.send),
            tooltip: 'Send test event',
            onPressed: () {
              context.read<WebhooksBloc>().add(TestWebhook(webhook.id));
            },
          ),
          IconButton(
            icon: Icon(webhook.isActive ? Icons.pause : Icons.play_arrow),
            tooltip: webhook.isActive ? 'Disable' : 'Enable',
            onPressed: () {
              context.read<WebhooksBloc>().add(
                    UpdateWebhook(id: webhook.id, isActive: !webhook.isActive),
                  );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'View deliveries',
            onPressed: () => _showDeliveriesDialog(context, webhook),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Edit',
            onPressed: () => _showEditDialog(context, webhook),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _showDeleteDialog(context, webhook),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => _WebhookFormDialog(
        bloc: context.read<WebhooksBloc>(),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WebhookInfo webhook) {
    showDialog(
      context: context,
      builder: (dialogContext) => _WebhookFormDialog(
        bloc: context.read<WebhooksBloc>(),
        webhook: webhook,
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WebhookInfo webhook) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Webhook'),
        content: Text(
          'Are you sure you want to delete the webhook for:\n\n${webhook.url}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              context.read<WebhooksBloc>().add(DeleteWebhook(webhook.id));
              Navigator.pop(dialogContext);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showDeliveriesDialog(BuildContext context, WebhookInfo webhook) {
    context.read<WebhooksBloc>().add(
          LoadWebhookDeliveries(webhookId: webhook.id),
        );

    showDialog(
      context: context,
      builder: (dialogContext) => _DeliveriesDialog(
        bloc: context.read<WebhooksBloc>(),
        webhookUrl: webhook.url,
      ),
    );
  }
}

class _WebhookFormDialog extends StatefulWidget {
  final WebhooksBloc bloc;
  final WebhookInfo? webhook;

  const _WebhookFormDialog({required this.bloc, this.webhook});

  @override
  State<_WebhookFormDialog> createState() => _WebhookFormDialogState();
}

class _WebhookFormDialogState extends State<_WebhookFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _urlController;
  late final TextEditingController _secretController;
  late final Set<String> _selectedEvents;
  bool _subscribeAll = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: widget.webhook?.url ?? '');
    _secretController = TextEditingController();
    if (widget.webhook != null) {
      _selectedEvents = Set.from(widget.webhook!.events);
      _subscribeAll = widget.webhook!.events.contains('*');
    } else {
      _selectedEvents = {};
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.webhook != null;

    return AlertDialog(
      title: Text(isEditing ? 'Edit Webhook' : 'Create Webhook'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Webhook URL',
                    hintText: 'https://example.com/webhook',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'URL is required';
                    }
                    final uri = Uri.tryParse(value);
                    if (uri == null ||
                        !uri.hasScheme ||
                        !['http', 'https'].contains(uri.scheme)) {
                      return 'Please enter a valid HTTP(S) URL';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (!isEditing) ...[
                  TextFormField(
                    controller: _secretController,
                    decoration: const InputDecoration(
                      labelText: 'Secret (optional)',
                      hintText: 'Used for HMAC signature verification',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Events',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Subscribe to all events'),
                  subtitle: const Text('Receive notifications for all event types'),
                  value: _subscribeAll,
                  onChanged: (value) {
                    setState(() {
                      _subscribeAll = value ?? false;
                      if (_subscribeAll) {
                        _selectedEvents.clear();
                        _selectedEvents.add('*');
                      } else {
                        _selectedEvents.remove('*');
                      }
                    });
                  },
                ),
                const Divider(),
                if (!_subscribeAll) ...[
                  ...WebhookEventTypes.all.map((event) {
                    return CheckboxListTile(
                      title: Text(WebhookEventTypes.displayName(event)),
                      subtitle: Text(event, style: const TextStyle(fontSize: 12)),
                      value: _selectedEvents.contains(event),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedEvents.add(event);
                          } else {
                            _selectedEvents.remove(event);
                          }
                        });
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: Text(isEditing ? 'Save' : 'Create'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final events = _subscribeAll ? ['*'] : _selectedEvents.toList();
    if (events.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one event')),
      );
      return;
    }

    if (widget.webhook != null) {
      widget.bloc.add(UpdateWebhook(
        id: widget.webhook!.id,
        url: _urlController.text,
        events: events,
      ));
    } else {
      widget.bloc.add(CreateWebhook(
        url: _urlController.text,
        events: events,
        secret: _secretController.text.isNotEmpty ? _secretController.text : null,
      ));
    }

    Navigator.pop(context);
  }
}

class _DeliveriesDialog extends StatelessWidget {
  final WebhooksBloc bloc;
  final String webhookUrl;

  const _DeliveriesDialog({required this.bloc, required this.webhookUrl});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WebhooksBloc, WebhooksState>(
      bloc: bloc,
      builder: (context, state) {
        return AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Recent Deliveries'),
              Text(
                webhookUrl,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          content: SizedBox(
            width: 600,
            height: 400,
            child: _buildDeliveriesContent(state),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDeliveriesContent(WebhooksState state) {
    if (state is WebhookDeliveriesLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is WebhookDeliveriesLoaded) {
      if (state.deliveries.isEmpty) {
        return const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inbox, size: 48, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'No deliveries yet',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        itemCount: state.deliveries.length,
        itemBuilder: (context, index) {
          final delivery = state.deliveries[index];
          final dateFormat = DateFormat('MMM d HH:mm:ss');

          return ListTile(
            leading: CircleAvatar(
              backgroundColor:
                  delivery.success ? Colors.green.shade100 : Colors.red.shade100,
              child: Icon(
                delivery.success ? Icons.check : Icons.close,
                color: delivery.success ? Colors.green : Colors.red,
                size: 20,
              ),
            ),
            title: Row(
              children: [
                Text(
                  WebhookEventTypes.displayName(delivery.eventType),
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(delivery.statusCode),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${delivery.statusCode}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '${dateFormat.format(delivery.deliveredAt.toLocal())} • ${delivery.durationMs}ms'
              '${delivery.error != null ? ' • ${delivery.error}' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
          );
        },
      );
    }

    return const Center(child: Text('Error loading deliveries'));
  }

  Color _getStatusColor(int statusCode) {
    if (statusCode >= 200 && statusCode < 300) return Colors.green;
    if (statusCode >= 400 && statusCode < 500) return Colors.orange;
    if (statusCode >= 500) return Colors.red;
    return Colors.grey;
  }
}
