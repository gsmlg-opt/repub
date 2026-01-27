import 'package:equatable/equatable.dart';

/// Represents the site-wide configuration for the registry.
class SiteConfig extends Equatable {
  final String baseUrl;
  final String listenAddr;
  final bool requireDownloadAuth;
  final String databaseType; // 'sqlite' or 'postgres'
  final String storageType; // 'local' or 's3'
  final int maxUploadSizeMb;
  final bool allowPublicRegistration;
  final int tokenMaxTtlDays; // 0 = unlimited
  final String? smtpHost;
  final int? smtpPort;
  final String? smtpFrom;

  const SiteConfig({
    required this.baseUrl,
    required this.listenAddr,
    required this.requireDownloadAuth,
    required this.databaseType,
    required this.storageType,
    required this.maxUploadSizeMb,
    required this.allowPublicRegistration,
    this.tokenMaxTtlDays = 0,
    this.smtpHost,
    this.smtpPort,
    this.smtpFrom,
  });

  factory SiteConfig.fromJson(Map<String, dynamic> json) {
    return SiteConfig(
      baseUrl: json['base_url'] as String,
      listenAddr: json['listen_addr'] as String,
      requireDownloadAuth: json['require_download_auth'] as bool? ?? false,
      databaseType: json['database_type'] as String,
      storageType: json['storage_type'] as String,
      maxUploadSizeMb: json['max_upload_size_mb'] as int? ?? 100,
      allowPublicRegistration:
          json['allow_public_registration'] as bool? ?? true,
      tokenMaxTtlDays: json['token_max_ttl_days'] as int? ?? 0,
      smtpHost: json['smtp_host'] as String?,
      smtpPort: json['smtp_port'] as int?,
      smtpFrom: json['smtp_from'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'base_url': baseUrl,
      'listen_addr': listenAddr,
      'require_download_auth': requireDownloadAuth,
      'database_type': databaseType,
      'storage_type': storageType,
      'max_upload_size_mb': maxUploadSizeMb,
      'allow_public_registration': allowPublicRegistration,
      'token_max_ttl_days': tokenMaxTtlDays,
      'smtp_host': smtpHost,
      'smtp_port': smtpPort,
      'smtp_from': smtpFrom,
    };
  }

  SiteConfig copyWith({
    String? baseUrl,
    String? listenAddr,
    bool? requireDownloadAuth,
    String? databaseType,
    String? storageType,
    int? maxUploadSizeMb,
    bool? allowPublicRegistration,
    int? tokenMaxTtlDays,
    String? smtpHost,
    int? smtpPort,
    String? smtpFrom,
  }) {
    return SiteConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      listenAddr: listenAddr ?? this.listenAddr,
      requireDownloadAuth: requireDownloadAuth ?? this.requireDownloadAuth,
      databaseType: databaseType ?? this.databaseType,
      storageType: storageType ?? this.storageType,
      maxUploadSizeMb: maxUploadSizeMb ?? this.maxUploadSizeMb,
      allowPublicRegistration:
          allowPublicRegistration ?? this.allowPublicRegistration,
      tokenMaxTtlDays: tokenMaxTtlDays ?? this.tokenMaxTtlDays,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      smtpFrom: smtpFrom ?? this.smtpFrom,
    );
  }

  @override
  List<Object?> get props => [
        baseUrl,
        listenAddr,
        requireDownloadAuth,
        databaseType,
        storageType,
        maxUploadSizeMb,
        allowPublicRegistration,
        tokenMaxTtlDays,
        smtpHost,
        smtpPort,
        smtpFrom,
      ];
}
