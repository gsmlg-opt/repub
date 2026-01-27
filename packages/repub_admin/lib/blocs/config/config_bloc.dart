import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/admin_api_client.dart';
import '../../models/site_config.dart';
import 'config_event.dart';
import 'config_state.dart';

/// BLoC that manages site configuration state and handles config events.
class ConfigBloc extends Bloc<ConfigEvent, ConfigState> {
  final AdminApiClient _apiClient;

  ConfigBloc({AdminApiClient? apiClient})
      : _apiClient = apiClient ?? AdminApiClient(),
        super(const ConfigInitial()) {
    on<LoadConfig>(_onLoadConfig);
    on<UpdateConfig>(_onUpdateConfig);
    on<UpdateConfigValue>(_onUpdateConfigValue);
  }

  Future<void> _onLoadConfig(
    LoadConfig event,
    Emitter<ConfigState> emit,
  ) async {
    emit(const ConfigLoading());
    try {
      final configList = await _apiClient.getConfig();

      // Convert list of SiteConfig entries to a single SiteConfig object
      // by reading individual config values
      final configMap = <String, String>{};
      for (final cfg in configList) {
        configMap[cfg.name] = cfg.value;
      }

      // Build SiteConfig from individual values
      // For now, we'll use placeholder values since the backend uses key-value pairs
      // TODO: Update backend to return structured config
      final config = SiteConfig(
        baseUrl: configMap['base_url'] ?? 'http://localhost:4920',
        listenAddr: configMap['listen_addr'] ?? '0.0.0.0:4920',
        requireDownloadAuth:
            configMap['require_download_auth'] == 'true' ? true : false,
        databaseType: configMap['database_type'] ?? 'sqlite',
        storageType: configMap['storage_type'] ?? 'local',
        maxUploadSizeMb: int.tryParse(configMap['max_upload_size_mb'] ?? '100') ?? 100,
        allowPublicRegistration:
            configMap['allow_public_registration'] != 'false',
        smtpHost: configMap['smtp_host'],
        smtpPort: int.tryParse(configMap['smtp_port'] ?? ''),
        smtpFrom: configMap['smtp_from'],
      );

      emit(ConfigLoaded(config));
    } catch (e) {
      emit(ConfigError('Failed to load configuration: $e'));
    }
  }

  Future<void> _onUpdateConfig(
    UpdateConfig event,
    Emitter<ConfigState> emit,
  ) async {
    emit(ConfigUpdating(event.config));
    try {
      // Update each config value individually
      await _apiClient.setConfig('base_url', event.config.baseUrl);
      await _apiClient.setConfig('listen_addr', event.config.listenAddr);
      await _apiClient.setConfig(
        'require_download_auth',
        event.config.requireDownloadAuth.toString(),
      );
      await _apiClient.setConfig('database_type', event.config.databaseType);
      await _apiClient.setConfig('storage_type', event.config.storageType);
      await _apiClient.setConfig(
        'max_upload_size_mb',
        event.config.maxUploadSizeMb.toString(),
      );
      await _apiClient.setConfig(
        'allow_public_registration',
        event.config.allowPublicRegistration.toString(),
      );

      if (event.config.smtpHost != null) {
        await _apiClient.setConfig('smtp_host', event.config.smtpHost!);
      }
      if (event.config.smtpPort != null) {
        await _apiClient.setConfig(
          'smtp_port',
          event.config.smtpPort.toString(),
        );
      }
      if (event.config.smtpFrom != null) {
        await _apiClient.setConfig('smtp_from', event.config.smtpFrom!);
      }

      emit(ConfigUpdateSuccess(
        'Configuration updated successfully',
        event.config,
      ));

      // Reload config to confirm changes
      add(const LoadConfig());
    } catch (e) {
      emit(ConfigUpdateError('Failed to update configuration: $e'));
    }
  }

  Future<void> _onUpdateConfigValue(
    UpdateConfigValue event,
    Emitter<ConfigState> emit,
  ) async {
    if (state is ConfigLoaded) {
      final currentConfig = (state as ConfigLoaded).config;
      emit(ConfigUpdating(currentConfig));

      try {
        await _apiClient.setConfig(event.name, event.value);
        emit(ConfigUpdateSuccess(
          'Configuration value "${event.name}" updated',
          currentConfig,
        ));

        // Reload config
        add(const LoadConfig());
      } catch (e) {
        emit(ConfigUpdateError('Failed to update ${event.name}: $e'));
      }
    }
  }
}
