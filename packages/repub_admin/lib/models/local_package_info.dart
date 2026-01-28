import 'package:equatable/equatable.dart';

/// Represents a locally hosted package in the registry with metadata and statistics.
class LocalPackageInfo extends Equatable {
  final String name;
  final String? description;
  final String latestVersion;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int downloadCount;
  final bool isDiscontinued;
  final List<String> versions;
  final String? uploaderEmail;

  const LocalPackageInfo({
    required this.name,
    this.description,
    required this.latestVersion,
    required this.createdAt,
    this.updatedAt,
    required this.downloadCount,
    required this.isDiscontinued,
    required this.versions,
    this.uploaderEmail,
  });

  factory LocalPackageInfo.fromJson(Map<String, dynamic> json) {
    return LocalPackageInfo(
      name: json['name'] as String,
      description: json['description'] as String?,
      latestVersion: json['latest_version'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      downloadCount: json['download_count'] as int? ?? 0,
      isDiscontinued: json['is_discontinued'] as bool? ?? false,
      versions: (json['versions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      uploaderEmail: json['uploader_email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'latest_version': latestVersion,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'download_count': downloadCount,
      'is_discontinued': isDiscontinued,
      'versions': versions,
      'uploader_email': uploaderEmail,
    };
  }

  @override
  List<Object?> get props => [
        name,
        description,
        latestVersion,
        createdAt,
        updatedAt,
        downloadCount,
        isDiscontinued,
        versions,
        uploaderEmail,
      ];
}
