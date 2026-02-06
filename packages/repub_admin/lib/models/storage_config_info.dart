import 'package:equatable/equatable.dart';

/// Represents a storage configuration (active or pending).
class StorageConfigDetail extends Equatable {
  final bool initialized;
  final String type; // 'local' or 's3'
  final String? localPath;
  final String? cachePath;
  final String? s3Endpoint;
  final String? s3Region;
  final String? s3Bucket;
  final String? s3AccessKey; // Masked in responses
  final String? s3SecretKey; // Masked in responses

  const StorageConfigDetail({
    required this.initialized,
    required this.type,
    this.localPath,
    this.cachePath,
    this.s3Endpoint,
    this.s3Region,
    this.s3Bucket,
    this.s3AccessKey,
    this.s3SecretKey,
  });

  factory StorageConfigDetail.fromJson(Map<String, dynamic> json) {
    return StorageConfigDetail(
      initialized: json['initialized'] as bool? ?? false,
      type: json['type'] as String? ?? 'local',
      localPath: json['localPath'] as String?,
      cachePath: json['cachePath'] as String?,
      s3Endpoint: json['s3Endpoint'] as String?,
      s3Region: json['s3Region'] as String?,
      s3Bucket: json['s3Bucket'] as String?,
      s3AccessKey: json['s3AccessKey'] as String?,
      s3SecretKey: json['s3SecretKey'] as String?,
    );
  }

  StorageConfigDetail copyWith({
    bool? initialized,
    String? type,
    String? localPath,
    String? cachePath,
    String? s3Endpoint,
    String? s3Region,
    String? s3Bucket,
    String? s3AccessKey,
    String? s3SecretKey,
  }) {
    return StorageConfigDetail(
      initialized: initialized ?? this.initialized,
      type: type ?? this.type,
      localPath: localPath ?? this.localPath,
      cachePath: cachePath ?? this.cachePath,
      s3Endpoint: s3Endpoint ?? this.s3Endpoint,
      s3Region: s3Region ?? this.s3Region,
      s3Bucket: s3Bucket ?? this.s3Bucket,
      s3AccessKey: s3AccessKey ?? this.s3AccessKey,
      s3SecretKey: s3SecretKey ?? this.s3SecretKey,
    );
  }

  @override
  List<Object?> get props => [
        initialized,
        type,
        localPath,
        cachePath,
        s3Endpoint,
        s3Region,
        s3Bucket,
        s3AccessKey,
        s3SecretKey,
      ];
}

/// Combined active and pending storage configuration.
class StorageConfigInfo extends Equatable {
  final StorageConfigDetail? active;
  final StorageConfigDetail? pending;

  const StorageConfigInfo({this.active, this.pending});

  factory StorageConfigInfo.fromJson(Map<String, dynamic> json) {
    return StorageConfigInfo(
      active: json['active'] != null
          ? StorageConfigDetail.fromJson(
              json['active'] as Map<String, dynamic>)
          : null,
      pending: json['pending'] != null
          ? StorageConfigDetail.fromJson(
              json['pending'] as Map<String, dynamic>)
          : null,
    );
  }

  bool get hasPending => pending != null && pending!.initialized;

  @override
  List<Object?> get props => [active, pending];
}
