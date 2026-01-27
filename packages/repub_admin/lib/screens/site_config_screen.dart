import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../blocs/config/config_bloc.dart';
import '../blocs/config/config_event.dart';
import '../blocs/config/config_state.dart';
import '../models/site_config.dart';
import '../widgets/admin_layout.dart';

class SiteConfigScreen extends StatefulWidget {
  const SiteConfigScreen({super.key});

  @override
  State<SiteConfigScreen> createState() => _SiteConfigScreenState();
}

class _SiteConfigScreenState extends State<SiteConfigScreen> {
  late SiteConfig _editedConfig;
  bool _hasChanges = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Load config when screen initializes
    context.read<ConfigBloc>().add(const LoadConfig());
  }

  void _onConfigChanged(SiteConfig newConfig) {
    setState(() {
      _editedConfig = newConfig;
      _hasChanges = true;
    });
  }

  void _saveConfig() {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<ConfigBloc>().add(UpdateConfig(_editedConfig));
    }
  }

  void _resetConfig(SiteConfig originalConfig) {
    setState(() {
      _editedConfig = originalConfig;
      _hasChanges = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentPath: '/config',
      child: BlocConsumer<ConfigBloc, ConfigState>(
        listener: (context, state) {
          if (state is ConfigUpdateSuccess) {
            setState(() {
              _hasChanges = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state is ConfigUpdateError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
              ),
            );
          } else if (state is ConfigLoaded) {
            setState(() {
              _editedConfig = state.config;
              _hasChanges = false;
            });
          }
        },
        builder: (context, state) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, state),
              Expanded(child: _buildContent(context, state)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ConfigState state) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Site Configuration',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage registry settings',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
          Row(
            children: [
              if (_hasChanges) ...[
                Chip(
                  label: const Text('Unsaved changes'),
                  backgroundColor: Colors.orange[100],
                  side: BorderSide(color: Colors.orange[300]!),
                ),
                const SizedBox(width: 16),
                OutlinedButton(
                  onPressed: state is ConfigLoaded
                      ? () => _resetConfig(state.config)
                      : null,
                  child: const Text('Reset'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: state is ConfigUpdating ? null : _saveConfig,
                  icon: state is ConfigUpdating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Save'),
                ),
              ],
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  context.read<ConfigBloc>().add(const LoadConfig());
                },
                tooltip: 'Reload',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, ConfigState state) {
    if (state is ConfigLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is ConfigError) {
      return _buildError(context, state.message);
    }

    if (state is ConfigLoaded ||
        state is ConfigUpdating ||
        state is ConfigUpdateSuccess) {
      return Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildServerSettingsCard(context),
              const SizedBox(height: 24),
              _buildAuthenticationCard(context),
              const SizedBox(height: 24),
              _buildStorageCard(context),
              const SizedBox(height: 24),
              _buildEmailCard(context),
            ],
          ),
        ),
      );
    }

    // Initial state - show loading
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildServerSettingsCard(BuildContext context) {
    return _buildSectionCard(
      context,
      title: 'Server Settings',
      icon: Icons.dns,
      children: [
        _buildTextField(
          label: 'Base URL',
          value: _editedConfig.baseUrl,
          hint: 'https://pub.example.com',
          readOnly: true,
          helpText: 'Set via REPUB_BASE_URL environment variable',
          onChanged: (value) {
            _onConfigChanged(_editedConfig.copyWith(baseUrl: value));
          },
        ),
        const SizedBox(height: 16),
        _buildTextField(
          label: 'Listen Address',
          value: _editedConfig.listenAddr,
          hint: '0.0.0.0:4920',
          readOnly: true,
          helpText: 'Set via REPUB_LISTEN_ADDR environment variable',
          onChanged: (value) {
            _onConfigChanged(_editedConfig.copyWith(listenAddr: value));
          },
        ),
      ],
    );
  }

  Widget _buildAuthenticationCard(BuildContext context) {
    return _buildSectionCard(
      context,
      title: 'Authentication',
      icon: Icons.security,
      children: [
        _buildSwitchTile(
          title: 'Require Download Authentication',
          subtitle:
              'When enabled, package downloads require a valid auth token',
          value: _editedConfig.requireDownloadAuth,
          onChanged: (value) {
            _onConfigChanged(
                _editedConfig.copyWith(requireDownloadAuth: value));
          },
        ),
        const Divider(),
        _buildSwitchTile(
          title: 'Allow Public Registration',
          subtitle: 'When enabled, anyone can create a user account',
          value: _editedConfig.allowPublicRegistration,
          onChanged: (value) {
            _onConfigChanged(
                _editedConfig.copyWith(allowPublicRegistration: value));
          },
        ),
        const Divider(),
        _buildTokenExpirationField(),
      ],
    );
  }

  Widget _buildTokenExpirationField() {
    final value = _editedConfig.tokenMaxTtlDays;

    return ListTile(
      title: const Text('Maximum Token Lifetime'),
      subtitle: Text(
        value == 0
            ? 'Tokens never expire unless user specifies expiration'
            : 'Tokens will expire after maximum $value days',
      ),
      trailing: SizedBox(
        width: 200,
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 0, child: Text('Unlimited')),
            DropdownMenuItem(value: 7, child: Text('7 days')),
            DropdownMenuItem(value: 30, child: Text('30 days')),
            DropdownMenuItem(value: 90, child: Text('90 days')),
            DropdownMenuItem(value: 180, child: Text('180 days')),
            DropdownMenuItem(value: 365, child: Text('1 year')),
          ],
          onChanged: (newValue) {
            if (newValue != null) {
              _onConfigChanged(
                  _editedConfig.copyWith(tokenMaxTtlDays: newValue));
            }
          },
        ),
      ),
    );
  }

  Widget _buildStorageCard(BuildContext context) {
    return _buildSectionCard(
      context,
      title: 'Storage',
      icon: Icons.storage,
      children: [
        Row(
          children: [
            Expanded(
              child: _buildReadOnlyField(
                label: 'Database Type',
                value: _editedConfig.databaseType.toUpperCase(),
                icon: _editedConfig.databaseType == 'sqlite'
                    ? Icons.folder
                    : Icons.cloud,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildReadOnlyField(
                label: 'Storage Type',
                value: _editedConfig.storageType.toUpperCase(),
                icon: _editedConfig.storageType == 'local'
                    ? Icons.folder
                    : Icons.cloud,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSliderField(
          label: 'Max Upload Size',
          value: _editedConfig.maxUploadSizeMb.toDouble(),
          min: 1,
          max: 100,
          divisions: 99,
          suffix: 'MB',
          onChanged: (value) {
            _onConfigChanged(
                _editedConfig.copyWith(maxUploadSizeMb: value.round()));
          },
        ),
      ],
    );
  }

  Widget _buildEmailCard(BuildContext context) {
    return _buildSectionCard(
      context,
      title: 'Email (Optional)',
      icon: Icons.email,
      children: [
        _buildTextField(
          label: 'SMTP Host',
          value: _editedConfig.smtpHost ?? '',
          hint: 'smtp.example.com',
          onChanged: (value) {
            _onConfigChanged(
                _editedConfig.copyWith(smtpHost: value.isEmpty ? null : value));
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                label: 'SMTP Port',
                value: _editedConfig.smtpPort?.toString() ?? '',
                hint: '587',
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  _onConfigChanged(_editedConfig.copyWith(
                    smtpPort: value.isEmpty ? null : int.tryParse(value),
                  ));
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                label: 'From Address',
                value: _editedConfig.smtpFrom ?? '',
                hint: 'noreply@example.com',
                keyboardType: TextInputType.emailAddress,
                onChanged: (value) {
                  _onConfigChanged(_editedConfig.copyWith(
                    smtpFrom: value.isEmpty ? null : value,
                  ));
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String value,
    required String hint,
    required Function(String) onChanged,
    bool readOnly = false,
    String? helpText,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          initialValue: value,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            filled: readOnly,
            fillColor: readOnly ? Colors.grey[100] : null,
            suffixIcon: readOnly
                ? Tooltip(
                    message: 'Set via environment variable',
                    child: Icon(Icons.lock, color: Colors.grey[500]),
                  )
                : null,
          ),
          readOnly: readOnly,
          keyboardType: keyboardType,
          onChanged: readOnly ? null : onChanged,
        ),
        if (helpText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12),
            child: Text(
              helpText,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildSliderField({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required Function(double) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                '${value.round()} $suffix',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: '${value.round()} $suffix',
          onChanged: onChanged,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${min.round()} $suffix',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              '${max.round()} $suffix',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, String error) {
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
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                context.read<ConfigBloc>().add(const LoadConfig());
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}
