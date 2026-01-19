/// A package in the registry.
class Package {
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDiscontinued;
  final String? replacedBy;

  const Package({
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.isDiscontinued = false,
    this.replacedBy,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
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
