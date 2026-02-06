import 'package:equatable/equatable.dart';
import '../../models/site_config.dart';
import '../../models/storage_config_info.dart';

/// Base class for all config events.
abstract class ConfigEvent extends Equatable {
  const ConfigEvent();

  @override
  List<Object?> get props => [];
}

/// Event to load site configuration.
class LoadConfig extends ConfigEvent {
  const LoadConfig();
}

/// Event to update site configuration.
class UpdateConfig extends ConfigEvent {
  final SiteConfig config;

  const UpdateConfig(this.config);

  @override
  List<Object?> get props => [config];
}

/// Event to update a single config value.
class UpdateConfigValue extends ConfigEvent {
  final String name;
  final String value;

  const UpdateConfigValue(this.name, this.value);

  @override
  List<Object?> get props => [name, value];
}

/// Event to save pending storage configuration.
class SavePendingStorageConfig extends ConfigEvent {
  final StorageConfigDetail pendingConfig;

  const SavePendingStorageConfig(this.pendingConfig);

  @override
  List<Object?> get props => [pendingConfig];
}
