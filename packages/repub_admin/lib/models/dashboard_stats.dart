import 'package:equatable/equatable.dart';

/// Represents dashboard statistics and metrics.
class DashboardStats extends Equatable {
  final int totalPackages;
  final int totalUsers;
  final int totalDownloads;
  final int activeTokens;
  final List<RecentActivity> recentActivity;
  final List<TopPackage> topPackages;

  const DashboardStats({
    required this.totalPackages,
    required this.totalUsers,
    required this.totalDownloads,
    required this.activeTokens,
    required this.recentActivity,
    required this.topPackages,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalPackages: json['total_packages'] as int? ?? 0,
      totalUsers: json['total_users'] as int? ?? 0,
      totalDownloads: json['total_downloads'] as int? ?? 0,
      activeTokens: json['active_tokens'] as int? ?? 0,
      recentActivity: (json['recent_activity'] as List<dynamic>?)
              ?.map((e) => RecentActivity.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      topPackages: (json['top_packages'] as List<dynamic>?)
              ?.map((e) => TopPackage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'total_packages': totalPackages,
      'total_users': totalUsers,
      'total_downloads': totalDownloads,
      'active_tokens': activeTokens,
      'recent_activity': recentActivity.map((e) => e.toJson()).toList(),
      'top_packages': topPackages.map((e) => e.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [
        totalPackages,
        totalUsers,
        totalDownloads,
        activeTokens,
        recentActivity,
        topPackages,
      ];
}

/// Represents a recent activity item.
class RecentActivity extends Equatable {
  final String id;
  final String type; // 'package_published', 'user_registered', 'download', etc.
  final String description;
  final DateTime timestamp;
  final String? actorEmail;
  final String? targetPackage;

  const RecentActivity({
    required this.id,
    required this.type,
    required this.description,
    required this.timestamp,
    this.actorEmail,
    this.targetPackage,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      id: json['id'] as String,
      type: json['type'] as String,
      description: json['description'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      actorEmail: json['actor_email'] as String?,
      targetPackage: json['target_package'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'description': description,
      'timestamp': timestamp.toIso8601String(),
      'actor_email': actorEmail,
      'target_package': targetPackage,
    };
  }

  @override
  List<Object?> get props =>
      [id, type, description, timestamp, actorEmail, targetPackage];
}

/// Represents a top package by downloads.
class TopPackage extends Equatable {
  final String name;
  final int downloadCount;
  final String latestVersion;

  const TopPackage({
    required this.name,
    required this.downloadCount,
    required this.latestVersion,
  });

  factory TopPackage.fromJson(Map<String, dynamic> json) {
    return TopPackage(
      name: json['name'] as String,
      downloadCount: json['download_count'] as int,
      latestVersion: json['latest_version'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'download_count': downloadCount,
      'latest_version': latestVersion,
    };
  }

  @override
  List<Object?> get props => [name, downloadCount, latestVersion];
}
