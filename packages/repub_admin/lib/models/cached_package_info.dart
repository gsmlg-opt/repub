import 'package:equatable/equatable.dart';

/// Represents a package cached from upstream registry (e.g., pub.dev).
class CachedPackageInfo extends Equatable {
  final String name;
  final String? description;
  final String latestVersion;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<String> versions;
  final String source;

  const CachedPackageInfo({
    required this.name,
    this.description,
    required this.latestVersion,
    required this.createdAt,
    this.updatedAt,
    required this.versions,
    this.source = 'pub.dev',
  });

  factory CachedPackageInfo.fromJson(Map<String, dynamic> json) {
    return CachedPackageInfo(
      name: json['name'] as String,
      description: json['description'] as String?,
      latestVersion: json['latest_version'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      versions: (json['versions'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      source: json['source'] as String? ?? 'pub.dev',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'latest_version': latestVersion,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'versions': versions,
      'source': source,
    };
  }

  @override
  List<Object?> get props => [
        name,
        description,
        latestVersion,
        createdAt,
        updatedAt,
        versions,
        source,
      ];
}
