import 'dart:convert';
import 'dart:io';

import 'metadata.dart';

/// Backup format version for compatibility checking.
const backupFormatVersion = 1;

/// Backup data structure containing all exportable data.
class BackupData {
  final int formatVersion;
  final DateTime createdAt;
  final String databaseType;
  final List<Map<String, dynamic>> packages;
  final List<Map<String, dynamic>> packageVersions;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> adminUsers;
  final List<Map<String, dynamic>> authTokens;
  final List<Map<String, dynamic>> activityLog;

  BackupData({
    required this.formatVersion,
    required this.createdAt,
    required this.databaseType,
    required this.packages,
    required this.packageVersions,
    required this.users,
    required this.adminUsers,
    required this.authTokens,
    required this.activityLog,
  });

  Map<String, dynamic> toJson() => {
        'formatVersion': formatVersion,
        'createdAt': createdAt.toIso8601String(),
        'databaseType': databaseType,
        'data': {
          'packages': packages,
          'packageVersions': packageVersions,
          'users': users,
          'adminUsers': adminUsers,
          'authTokens': authTokens,
          'activityLog': activityLog,
        },
      };

  factory BackupData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>;
    return BackupData(
      formatVersion: json['formatVersion'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      databaseType: json['databaseType'] as String,
      packages: (data['packages'] as List<dynamic>)
          .cast<Map<String, dynamic>>(),
      packageVersions: (data['packageVersions'] as List<dynamic>)
          .cast<Map<String, dynamic>>(),
      users: (data['users'] as List<dynamic>).cast<Map<String, dynamic>>(),
      adminUsers:
          (data['adminUsers'] as List<dynamic>).cast<Map<String, dynamic>>(),
      authTokens:
          (data['authTokens'] as List<dynamic>).cast<Map<String, dynamic>>(),
      activityLog:
          (data['activityLog'] as List<dynamic>).cast<Map<String, dynamic>>(),
    );
  }

  /// Get summary statistics of the backup.
  Map<String, int> get summary => {
        'packages': packages.length,
        'packageVersions': packageVersions.length,
        'users': users.length,
        'adminUsers': adminUsers.length,
        'authTokens': authTokens.length,
        'activityLog': activityLog.length,
      };
}

/// Database backup/restore utilities.
class BackupManager {
  final MetadataStore metadata;

  BackupManager(this.metadata);

  /// Create a backup of all database data.
  ///
  /// Note: This does NOT backup blob storage (package archives).
  /// Blob storage should be backed up separately using appropriate tools
  /// (e.g., filesystem copy for local storage, S3 bucket replication for S3).
  Future<BackupData> createBackup() async {
    final databaseType = metadata is SqliteMetadataStore
        ? 'sqlite'
        : 'postgresql';

    return BackupData(
      formatVersion: backupFormatVersion,
      createdAt: DateTime.now().toUtc(),
      databaseType: databaseType,
      packages: await _exportPackages(),
      packageVersions: await _exportPackageVersions(),
      users: await _exportUsers(),
      adminUsers: await _exportAdminUsers(),
      authTokens: await _exportAuthTokens(),
      activityLog: await _exportActivityLog(),
    );
  }

  /// Export backup to a JSON file.
  Future<void> exportToFile(String filePath) async {
    final backup = await createBackup();
    final json = const JsonEncoder.withIndent('  ').convert(backup.toJson());
    final file = File(filePath);
    await file.writeAsString(json);
  }

  /// Import backup from a JSON file.
  ///
  /// WARNING: This will clear existing data before importing!
  /// Returns a summary of imported records.
  Future<Map<String, int>> importFromFile(String filePath, {bool dryRun = false}) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw BackupException('Backup file not found: $filePath');
    }

    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    final backup = BackupData.fromJson(json);

    // Validate backup format
    if (backup.formatVersion > backupFormatVersion) {
      throw BackupException(
        'Backup format version ${backup.formatVersion} is newer than supported version $backupFormatVersion. '
        'Please upgrade repub to restore this backup.',
      );
    }

    if (dryRun) {
      return backup.summary;
    }

    // Import data
    await _importUsers(backup.users);
    await _importAdminUsers(backup.adminUsers);
    await _importAuthTokens(backup.authTokens);
    await _importPackages(backup.packages);
    await _importPackageVersions(backup.packageVersions);
    await _importActivityLog(backup.activityLog);

    return backup.summary;
  }

  // Export methods
  Future<List<Map<String, dynamic>>> _exportPackages() async {
    if (metadata is SqliteMetadataStore) {
      return (metadata as SqliteMetadataStore).exportPackages();
    } else {
      return (metadata as PostgresMetadataStore).exportPackages();
    }
  }

  Future<List<Map<String, dynamic>>> _exportPackageVersions() async {
    if (metadata is SqliteMetadataStore) {
      return (metadata as SqliteMetadataStore).exportPackageVersions();
    } else {
      return (metadata as PostgresMetadataStore).exportPackageVersions();
    }
  }

  Future<List<Map<String, dynamic>>> _exportUsers() async {
    if (metadata is SqliteMetadataStore) {
      return (metadata as SqliteMetadataStore).exportUsers();
    } else {
      return (metadata as PostgresMetadataStore).exportUsers();
    }
  }

  Future<List<Map<String, dynamic>>> _exportAdminUsers() async {
    if (metadata is SqliteMetadataStore) {
      return (metadata as SqliteMetadataStore).exportAdminUsers();
    } else {
      return (metadata as PostgresMetadataStore).exportAdminUsers();
    }
  }

  Future<List<Map<String, dynamic>>> _exportAuthTokens() async {
    if (metadata is SqliteMetadataStore) {
      return (metadata as SqliteMetadataStore).exportAuthTokens();
    } else {
      return (metadata as PostgresMetadataStore).exportAuthTokens();
    }
  }

  Future<List<Map<String, dynamic>>> _exportActivityLog() async {
    if (metadata is SqliteMetadataStore) {
      return (metadata as SqliteMetadataStore).exportActivityLog();
    } else {
      return (metadata as PostgresMetadataStore).exportActivityLog();
    }
  }

  // Import methods
  Future<void> _importUsers(List<Map<String, dynamic>> users) async {
    if (metadata is SqliteMetadataStore) {
      await (metadata as SqliteMetadataStore).importUsers(users);
    } else {
      await (metadata as PostgresMetadataStore).importUsers(users);
    }
  }

  Future<void> _importAdminUsers(List<Map<String, dynamic>> adminUsers) async {
    if (metadata is SqliteMetadataStore) {
      await (metadata as SqliteMetadataStore).importAdminUsers(adminUsers);
    } else {
      await (metadata as PostgresMetadataStore).importAdminUsers(adminUsers);
    }
  }

  Future<void> _importAuthTokens(List<Map<String, dynamic>> tokens) async {
    if (metadata is SqliteMetadataStore) {
      await (metadata as SqliteMetadataStore).importAuthTokens(tokens);
    } else {
      await (metadata as PostgresMetadataStore).importAuthTokens(tokens);
    }
  }

  Future<void> _importPackages(List<Map<String, dynamic>> packages) async {
    if (metadata is SqliteMetadataStore) {
      await (metadata as SqliteMetadataStore).importPackages(packages);
    } else {
      await (metadata as PostgresMetadataStore).importPackages(packages);
    }
  }

  Future<void> _importPackageVersions(List<Map<String, dynamic>> versions) async {
    if (metadata is SqliteMetadataStore) {
      await (metadata as SqliteMetadataStore).importPackageVersions(versions);
    } else {
      await (metadata as PostgresMetadataStore).importPackageVersions(versions);
    }
  }

  Future<void> _importActivityLog(List<Map<String, dynamic>> activities) async {
    if (metadata is SqliteMetadataStore) {
      await (metadata as SqliteMetadataStore).importActivityLog(activities);
    } else {
      await (metadata as PostgresMetadataStore).importActivityLog(activities);
    }
  }
}

/// Exception thrown during backup/restore operations.
class BackupException implements Exception {
  final String message;
  BackupException(this.message);

  @override
  String toString() => 'BackupException: $message';
}
