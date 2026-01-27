/// A package in the registry.
///
/// Packages can be one of two types:
/// - **Hosted packages** (isUpstreamCache=false): Packages published directly to this registry
/// - **Cached packages** (isUpstreamCache=true): Packages cached from upstream registry (pub.dev)
///
/// These are fundamentally different entities with different lifecycles:
/// - Hosted packages are owned, managed, and published by users of this registry
/// - Cached packages are read-only mirrors fetched from upstream on first download
class Package {
  final String name;
  final String? ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDiscontinued;
  final String? replacedBy;

  /// Whether this package is cached from an upstream registry (pub.dev).
  /// If true, this is a cached package and cannot be published to directly.
  /// If false, this is a hosted package that was published to this registry.
  final bool isUpstreamCache;

  const Package({
    required this.name,
    this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    this.isDiscontinued = false,
    this.replacedBy,
    this.isUpstreamCache = false,
  });

  /// Check if a user can publish to this package.
  bool canPublish(String? userId) {
    // Upstream cached packages cannot be published to
    if (isUpstreamCache) return false;
    // No owner means anyone can publish (legacy packages)
    if (ownerId == null) return true;
    // Owner can always publish
    return ownerId == userId;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (ownerId != null) 'ownerId': ownerId,
        if (isDiscontinued) 'isDiscontinued': true,
        if (replacedBy != null) 'replacedBy': replacedBy,
      };
}

/// A specific version of a package.
class PackageVersion {
  final String packageName;
  final String version;
  final Map<String, dynamic> pubspec;
  final String archiveKey;
  final String archiveSha256;
  final DateTime publishedAt;

  const PackageVersion({
    required this.packageName,
    required this.version,
    required this.pubspec,
    required this.archiveKey,
    required this.archiveSha256,
    required this.publishedAt,
  });

  /// Convert to JSON for API response.
  /// [archiveUrl] is the full URL to download the archive.
  Map<String, dynamic> toJson(String archiveUrl) => {
        'version': version,
        'pubspec': pubspec,
        'archive_url': archiveUrl,
        'archive_sha256': archiveSha256,
        'published': publishedAt.toUtc().toIso8601String(),
      };
}

/// Full package info including all versions.
class PackageInfo {
  final Package package;
  final List<PackageVersion> versions;

  const PackageInfo({required this.package, required this.versions});

  /// Get the latest version (highest semver).
  PackageVersion? get latest {
    if (versions.isEmpty) return null;
    final sorted = List<PackageVersion>.from(versions)
      ..sort((a, b) => _compareSemver(b.version, a.version));
    return sorted.first;
  }
}

/// Simple semver comparison (handles x.y.z format).
int _compareSemver(String a, String b) {
  final aParts = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final bParts = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();

  for (var i = 0; i < 3; i++) {
    final aVal = i < aParts.length ? aParts[i] : 0;
    final bVal = i < bParts.length ? bParts[i] : 0;
    if (aVal != bVal) return aVal.compareTo(bVal);
  }
  return 0;
}

/// Admin dashboard statistics.
class AdminStats {
  final int totalPackages;
  final int localPackages;
  final int cachedPackages;
  final int totalVersions;

  const AdminStats({
    required this.totalPackages,
    required this.localPackages,
    required this.cachedPackages,
    required this.totalVersions,
  });

  Map<String, dynamic> toJson() => {
        'totalPackages': totalPackages,
        'localPackages': localPackages,
        'cachedPackages': cachedPackages,
        'totalVersions': totalVersions,
      };

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
        totalPackages: json['totalPackages'] as int,
        localPackages: json['localPackages'] as int,
        cachedPackages: json['cachedPackages'] as int,
        totalVersions: json['totalVersions'] as int,
      );
}

/// Result of listing packages with pagination.
class PackageListResult {
  final List<PackageInfo> packages;
  final int total;
  final int page;
  final int limit;

  const PackageListResult({
    required this.packages,
    required this.total,
    required this.page,
    required this.limit,
  });

  int get totalPages => (total / limit).ceil();
  bool get hasNextPage => page < totalPages;
  bool get hasPrevPage => page > 1;

  Map<String, dynamic> toJson(String baseUrl) => {
        'packages': packages.map((p) {
          final latest = p.latest;
          final latestArchiveUrl = latest != null
              ? '$baseUrl/packages/${latest.packageName}/versions/${latest.version}.tar.gz'
              : null;
          return {
            'name': p.package.name,
            if (latest != null) 'latest': latest.toJson(latestArchiveUrl!),
            'versions': p.versions.map((v) {
              final archiveUrl =
                  '$baseUrl/packages/${v.packageName}/versions/${v.version}.tar.gz';
              return v.toJson(archiveUrl);
            }).toList(),
            if (p.package.isDiscontinued) 'isDiscontinued': true,
            if (p.package.replacedBy != null)
              'replacedBy': p.package.replacedBy,
          };
        }).toList(),
        'total': total,
        'page': page,
        'limit': limit,
      };
}
