/// Download statistics for a package.
class PackageDownloadStats {
  /// Package name.
  final String packageName;

  /// Total downloads across all versions.
  final int totalDownloads;

  /// Downloads grouped by version.
  final Map<String, int> downloadsByVersion;

  /// Daily download counts for recent history.
  /// Key is date (YYYY-MM-DD), value is download count.
  final Map<String, int> dailyDownloads;

  const PackageDownloadStats({
    required this.packageName,
    required this.totalDownloads,
    required this.downloadsByVersion,
    required this.dailyDownloads,
  });

  Map<String, dynamic> toJson() => {
        'package_name': packageName,
        'total_downloads': totalDownloads,
        'downloads_by_version': downloadsByVersion,
        'daily_downloads': dailyDownloads,
      };

  factory PackageDownloadStats.fromJson(Map<String, dynamic> json) {
    return PackageDownloadStats(
      packageName: json['package_name'] as String,
      totalDownloads: json['total_downloads'] as int,
      downloadsByVersion: (json['downloads_by_version'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)),
      dailyDownloads: (json['daily_downloads'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)),
    );
  }
}
