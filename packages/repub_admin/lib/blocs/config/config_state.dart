import 'package:equatable/equatable.dart';
import '../../models/site_config.dart';
import '../../models/storage_config_info.dart';

/// Base class for all config states.
abstract class ConfigState extends Equatable {
  const ConfigState();

  @override
  List<Object?> get props => [];
}

/// Initial state before any data is loaded.
class ConfigInitial extends ConfigState {
  const ConfigInitial();
}

/// State when config is being loaded.
class ConfigLoading extends ConfigState {
  const ConfigLoading();
}

/// State when config is successfully loaded.
class ConfigLoaded extends ConfigState {
  final SiteConfig config;
  final StorageConfigInfo? storageConfig;

  const ConfigLoaded(this.config, {this.storageConfig});

  @override
  List<Object?> get props => [config, storageConfig];
}

/// State when config loading fails.
class ConfigError extends ConfigState {
  final String message;

  const ConfigError(this.message);

  @override
  List<Object?> get props => [message];
}

/// State when config is being updated.
class ConfigUpdating extends ConfigState {
  final SiteConfig config; // Current config being edited

  const ConfigUpdating(this.config);

  @override
  List<Object?> get props => [config];
}

/// State when config update succeeds.
class ConfigUpdateSuccess extends ConfigState {
  final String message;
  final SiteConfig config;

  const ConfigUpdateSuccess(this.message, this.config);

  @override
  List<Object?> get props => [message, config];
}

/// State when config update fails.
class ConfigUpdateError extends ConfigState {
  final String message;

  const ConfigUpdateError(this.message);

  @override
  List<Object?> get props => [message];
}
