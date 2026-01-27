import 'package:equatable/equatable.dart';

/// Download statistics for a package.
class PackageStats extends Equatable {
  final String packageName;
  final int totalDownloads;
  final Map<String, int> downloadsByVersion;
  final Map<String, int> dailyDownloads;
  final int versionCount;
  final String? latestVersion;

  const PackageStats({
    required this.packageName,
    required this.totalDownloads,
    required this.downloadsByVersion,
    required this.dailyDownloads,
    required this.versionCount,
    this.latestVersion,
  });

  factory PackageStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? {};
    return PackageStats(
      packageName: json['package']?['name'] as String? ??
          stats['package_name'] as String? ??
          '',
      totalDownloads: stats['total_downloads'] as int? ?? 0,
      downloadsByVersion:
          (stats['downloads_by_version'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, v as int)) ??
              {},
      dailyDownloads: (stats['daily_downloads'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int)) ??
          {},
      versionCount: json['version_count'] as int? ?? 0,
      latestVersion: json['latest_version'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        packageName,
        totalDownloads,
        downloadsByVersion,
        dailyDownloads,
        versionCount,
        latestVersion,
      ];
}
