import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:repub_model/repub_model.dart';

import '../widgets/admin_layout.dart';
import 'dashboard_screen.dart';

final siteConfigProvider = FutureProvider<List<SiteConfig>>((ref) async {
  final client = ref.watch(adminApiClientProvider);
  return client.getConfig();
});

class SiteConfigScreen extends ConsumerWidget {
  const SiteConfigScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(siteConfigProvider);

    return AdminLayout(
      currentPath: '/config',
      child: configAsync.when(
        data: (configs) => _buildContent(context, ref, configs),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => _buildError(context, error.toString(), ref),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    List<SiteConfig> configs,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Site Configuration',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              FilledButton.icon(
                onPressed: () => ref.refresh(siteConfigProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Configure site-wide settings for your Repub instance',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 24),
          _buildConfigSections(context, ref, configs),
        ],
      ),
    );
  }

  Widget _buildConfigSections(
    BuildContext context,
    WidgetRef ref,
    List<SiteConfig> configs,
  ) {
    // Group configs by category
    final authConfigs = configs
        .where((c) =>
            c.name.contains('registration') ||
            c.name.contains('publish') ||
            c.name.contains('verification'))
        .toList();
    final sessionConfigs = configs
        .where((c) => c.name.contains('session') || c.name.contains('token'))
        .toList();
    final oauthConfigs =
        configs.where((c) => c.name.contains('oauth')).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (authConfigs.isNotEmpty) ...[
          _buildSection(
            context,
            ref,
            'Authentication & Publishing',
            authConfigs,
            Icons.security,
          ),
          const SizedBox(height: 24),
        ],
        if (sessionConfigs.isNotEmpty) ...[
          _buildSection(
            context,
            ref,
            'Sessions & Tokens',
            sessionConfigs,
            Icons.access_time,
          ),
          const SizedBox(height: 24),
        ],
        if (oauthConfigs.isNotEmpty) ...[
          _buildSection(
            context,
            ref,
            'OAuth Providers',
            oauthConfigs,
            Icons.vpn_key,
          ),
        ],
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    WidgetRef ref,
    String title,
    List<SiteConfig> configs,
    IconData icon,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: Theme.of(context).primaryColor),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            ...configs.map((config) => _buildConfigItem(context, ref, config)),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigItem(
    BuildContext context,
    WidgetRef ref,
    SiteConfig config,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatConfigName(config.name),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (config.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        config.description!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 24),
              SizedBox(
                width: 300,
                child: _buildConfigInput(context, ref, config),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfigInput(
    BuildContext context,
    WidgetRef ref,
    SiteConfig config,
  ) {
    switch (config.valueType) {
      case ConfigValueType.boolean:
        return _buildBooleanInput(context, ref, config);
      case ConfigValueType.number:
        return _buildNumberInput(context, ref, config);
      case ConfigValueType.string:
      case ConfigValueType.json:
        return _buildTextInput(context, ref, config);
    }
  }

  Widget _buildBooleanInput(
    BuildContext context,
    WidgetRef ref,
    SiteConfig config,
  ) {
    return SwitchListTile(
      value: config.boolValue,
      onChanged: (value) => _updateConfig(ref, config.name, value.toString()),
      contentPadding: EdgeInsets.zero,
      title: Text(config.boolValue ? 'Enabled' : 'Disabled'),
    );
  }

  Widget _buildNumberInput(
    BuildContext context,
    WidgetRef ref,
    SiteConfig config,
  ) {
    final controller = TextEditingController(text: config.value);
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.save),
          onPressed: () => _updateConfig(ref, config.name, controller.text),
        ),
      ),
      onSubmitted: (value) => _updateConfig(ref, config.name, value),
    );
  }

  Widget _buildTextInput(
    BuildContext context,
    WidgetRef ref,
    SiteConfig config,
  ) {
    final controller = TextEditingController(text: config.value);
    final isSecret = config.name.contains('secret');

    return TextField(
      controller: controller,
      obscureText: isSecret,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: const Icon(Icons.save),
          onPressed: () => _updateConfig(ref, config.name, controller.text),
        ),
      ),
      onSubmitted: (value) => _updateConfig(ref, config.name, value),
    );
  }

  Future<void> _updateConfig(WidgetRef ref, String name, String value) async {
    try {
      final client = ref.read(adminApiClientProvider);
      await client.setConfig(name, value);

      // Refresh the config list
      ref.invalidate(siteConfigProvider);

      // Show success message (would need a scaffold messenger in real app)
    } catch (e) {
      // Show error message
      debugPrint('Error updating config: $e');
    }
  }

  String _formatConfigName(String name) {
    // Convert snake_case to Title Case
    return name
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  Widget _buildError(BuildContext context, String error, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Failed to load configuration',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.refresh(siteConfigProvider),
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
