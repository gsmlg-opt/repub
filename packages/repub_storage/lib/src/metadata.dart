import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:postgres/postgres.dart';
import 'package:repub_model/repub_model.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

/// Abstract metadata storage interface.
abstract class MetadataStore {
  static const _uuid = Uuid();

  /// Create a MetadataStore from config.
  /// Uses SQLite if database URL is a file path or sqlite:// scheme,
  /// otherwise uses PostgreSQL.
  static Future<MetadataStore> create(Config config) async {
    if (config.databaseType == DatabaseType.sqlite) {
      return SqliteMetadataStore.open(config.sqlitePath);
    } else {
      final conn = await _connectPostgres(
        config.databaseUrl,
        retryAttempts: config.databaseRetryAttempts,
        retryDelaySeconds: config.databaseRetryDelaySeconds,
      );
      return PostgresMetadataStore(conn);
    }
  }

  static Future<Connection> _connectPostgres(
    String databaseUrl, {
    int retryAttempts = 30,
    int retryDelaySeconds = 1,
  }) async {
    final uri = Uri.parse(databaseUrl);
    final userInfo = uri.userInfo.split(':');

    final endpoint = Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'repub',
      username: userInfo.isNotEmpty ? userInfo[0] : 'repub',
      password: userInfo.length > 1 ? userInfo[1] : 'repub',
    );

    for (var i = 0; i < retryAttempts; i++) {
      try {
        return await Connection.open(
          endpoint,
          settings: ConnectionSettings(sslMode: SslMode.disable),
        );
      } catch (e) {
        if (i == retryAttempts - 1) rethrow;
        Logger.info('Waiting for database connection...',
            component: 'database',
            metadata: {'attempt': i + 1, 'maxAttempts': retryAttempts});
        await Future.delayed(Duration(seconds: retryDelaySeconds));
      }
    }
    throw StateError('Could not connect to database');
  }

  /// Run database migrations.
  Future<int> runMigrations();

  /// Drop all tables from the database.
  /// WARNING: This is a destructive operation that will delete all data!
  Future<void> dropAllTables();

  /// Close the database connection.
  Future<void> close();

  /// Check database health.
  /// Returns a map with health status information.
  Future<Map<String, dynamic>> healthCheck();

  // ============ Packages ============

  /// Get a package by name, returns null if not found.
  Future<Package?> getPackage(String name);

  /// Get all versions of a package.
  Future<List<PackageVersion>> getPackageVersions(String packageName);

  /// Get full package info including all versions.
  Future<PackageInfo?> getPackageInfo(String name);

  /// Get a specific version of a package.
  Future<PackageVersion?> getPackageVersion(String packageName, String version);

  /// Create or update a package and add a new version.
  /// If [isUpstreamCache] is true, the package is cached from upstream.
  /// If [ownerId] is provided, it sets the package owner (for new packages only).
  Future<void> upsertPackageVersion({
    required String packageName,
    required String version,
    required Map<String, dynamic> pubspec,
    required String archiveKey,
    required String archiveSha256,
    bool isUpstreamCache = false,
    String? ownerId,
  });

  /// Check if a version already exists.
  Future<bool> versionExists(String packageName, String version);

  /// List all packages with pagination.
  Future<PackageListResult> listPackages({int page = 1, int limit = 20});

  /// Search packages by name or description.
  Future<PackageListResult> searchPackages(String query,
      {int page = 1, int limit = 20});

  // ============ Auth Tokens ============

  /// Get a token by its hash.
  Future<AuthToken?> getTokenByHash(String tokenHash);

  /// Update last_used_at for a token.
  Future<void> touchToken(String tokenHash);

  /// Create a new token for a user, returns the plaintext token.
  Future<String> createToken({
    required String userId,
    required String label,
    List<String>? scopes,
    DateTime? expiresAt,
  });

  /// List tokens, optionally filtered by user.
  Future<List<AuthToken>> listTokens({String? userId});

  /// Delete a token by label.
  Future<bool> deleteToken(String label);

  // ============ Upload Sessions ============

  /// Create an upload session.
  Future<UploadSession> createUploadSession({
    Duration ttl = const Duration(hours: 1),
  });

  /// Get an upload session by ID.
  Future<UploadSession?> getUploadSession(String id);

  /// Mark an upload session as completed.
  Future<void> completeUploadSession(String id);

  /// Clean up expired sessions.
  Future<int> cleanupExpiredSessions();

  // ============ Admin Operations ============

  /// List packages filtered by type (local vs cached).
  Future<PackageListResult> listPackagesByType({
    required bool isUpstreamCache,
    int page = 1,
    int limit = 20,
  });

  /// Delete a package and all its versions. Returns version count deleted.
  Future<int> deletePackage(String name);

  /// Delete a single package version.
  Future<bool> deletePackageVersion(String name, String version);

  /// Retract a package version (soft delete - marks as retracted but keeps data).
  /// [message] is an optional explanation (e.g., "Security vulnerability").
  Future<bool> retractPackageVersion(
    String name,
    String version, {
    String? message,
  });

  /// Unretract a previously retracted package version.
  Future<bool> unretractPackageVersion(String name, String version);

  /// Mark a package as discontinued.
  Future<bool> discontinuePackage(String name, {String? replacedBy});

  /// Transfer package ownership to a new owner.
  /// Returns true if the transfer was successful.
  /// Returns false if the package doesn't exist or the new owner doesn't exist.
  Future<bool> transferPackageOwnership(
    String packageName,
    String newOwnerId,
  );

  /// Delete all upstream-cached packages. Returns package count deleted.
  Future<int> clearAllCachedPackages();

  /// Get admin statistics.
  Future<AdminStats> getAdminStats();

  /// Count total users.
  Future<int> countUsers();

  /// Count active tokens.
  Future<int> countActiveTokens();

  /// Get total download count.
  Future<int> getTotalDownloads();

  // ============ Analytics ============

  /// Log a package download.
  Future<void> logDownload({
    required String packageName,
    required String version,
    String? ipAddress,
    String? userAgent,
  });

  /// Get packages created per day for the last N days.
  /// Returns a map of date (YYYY-MM-DD) to count.
  Future<Map<String, int>> getPackagesCreatedPerDay(int days);

  /// Get downloads per hour for the last N hours.
  /// Returns a map of datetime (YYYY-MM-DD HH:00:00) to count.
  Future<Map<String, int>> getDownloadsPerHour(int hours);

  /// Get download statistics for a specific package.
  /// Returns total downloads, downloads by version, and recent download history.
  Future<PackageDownloadStats> getPackageDownloadStats(String packageName,
      {int historyDays = 30});

  /// Get archive keys for a package (for blob deletion).
  Future<List<String>> getPackageArchiveKeys(String name);

  /// Get archive key for a specific version (for blob deletion).
  Future<String?> getVersionArchiveKey(String name, String version);

  // ============ Users ============

  /// Create a new user, returns the user ID.
  Future<String> createUser({
    required String email,
    String? passwordHash,
    String? name,
  });

  /// Get a user by ID.
  Future<User?> getUser(String id);

  /// Get a user by email.
  Future<User?> getUserByEmail(String email);

  /// Update a user's profile.
  Future<bool> updateUser(String id,
      {String? name, String? passwordHash, bool? isActive});

  /// Update user's last login timestamp.
  Future<void> touchUserLogin(String id);

  /// Delete a user (transfers packages to anonymous).
  Future<bool> deleteUser(String id);

  /// List all users with pagination.
  Future<List<User>> listUsers({int page = 1, int limit = 20});

  // ============ Site Config ============

  /// Get a site config value.
  Future<SiteConfig?> getConfig(String name);

  /// Set a site config value.
  Future<void> setConfig(String name, String value);

  /// Get all site config values.
  Future<List<SiteConfig>> getAllConfig();

  // ============ User Sessions ============

  /// Create a user session, returns the session object with ID.
  Future<UserSession> createUserSession({
    required String userId,
    Duration ttl = const Duration(hours: 24),
  });

  /// Get a user session by ID.
  Future<UserSession?> getUserSession(String sessionId);

  /// Delete a user session.
  Future<bool> deleteUserSession(String sessionId);

  /// Clean up expired user sessions.
  Future<int> cleanupExpiredUserSessions();

  // ============ Admin Users ============

  /// Create a new admin user, returns the user ID.
  Future<String> createAdminUser({
    required String username,
    required String passwordHash,
    String? name,
    bool mustChangePassword = false,
  });

  /// Get an admin user by ID.
  Future<AdminUser?> getAdminUser(String id);

  /// Get an admin user by username.
  Future<AdminUser?> getAdminUserByUsername(String username);

  /// Update an admin user's profile.
  Future<bool> updateAdminUser(String id,
      {String? name,
      String? passwordHash,
      bool? isActive,
      bool? mustChangePassword});

  /// Update admin's last login timestamp.
  Future<void> touchAdminLogin(String id);

  /// Delete an admin user.
  Future<bool> deleteAdminUser(String id);

  /// List all admin users with pagination.
  Future<List<AdminUser>> listAdminUsers({int page = 1, int limit = 20});

  /// Ensure a default admin user exists (username: admin, password: admin).
  /// Creates the user with mustChangePassword=true if no admin users exist.
  /// Returns true if a default admin was created.
  Future<bool> ensureDefaultAdminUser(String Function(String) hashPassword);

  // ============ Admin Sessions ============

  /// Create an admin session, returns the session object with ID.
  Future<UserSession> createAdminSession({
    required String adminUserId,
    Duration ttl = const Duration(hours: 8),
  });

  /// Get an admin session by ID.
  Future<UserSession?> getAdminSession(String sessionId);

  /// Delete an admin session.
  Future<bool> deleteAdminSession(String sessionId);

  // ============ Admin Login History ============

  /// Log an admin login attempt.
  Future<String> logAdminLogin({
    required String adminUserId,
    String? ipAddress,
    String? userAgent,
    bool success = true,
  });

  /// Get login history for a specific admin user.
  Future<List<AdminLoginHistory>> getAdminLoginHistory({
    required String adminUserId,
    int limit = 50,
  });

  /// Get recent login history across all admin users.
  Future<List<AdminLoginHistory>> getRecentAdminLogins({
    int limit = 100,
  });

  // ============ Activity Log ============

  /// Log an activity event.
  Future<String> logActivity({
    required String activityType,
    required String actorType,
    String? actorId,
    String? actorEmail,
    String? actorUsername,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? metadata,
    String? ipAddress,
  });

  /// Get recent activity log entries.
  Future<List<ActivityLog>> getRecentActivity({
    int limit = 10,
    String? activityType,
    String? actorType,
  });

  // ============ Webhook Operations ============

  /// Create a new webhook.
  Future<Webhook> createWebhook({
    required String url,
    String? secret,
    required List<String> events,
  });

  /// Get a webhook by ID.
  Future<Webhook?> getWebhook(String id);

  /// List all webhooks.
  Future<List<Webhook>> listWebhooks({bool activeOnly = false});

  /// Update a webhook.
  Future<void> updateWebhook(Webhook webhook);

  /// Delete a webhook.
  Future<void> deleteWebhook(String id);

  /// Get webhooks that should be triggered for an event type.
  Future<List<Webhook>> getWebhooksForEvent(String eventType);

  /// Log a webhook delivery attempt.
  Future<void> logWebhookDelivery(WebhookDelivery delivery);

  /// Get recent deliveries for a webhook.
  Future<List<WebhookDelivery>> getWebhookDeliveries(
    String webhookId, {
    int limit = 20,
  });
}

/// Metadata storage backed by PostgreSQL.
class PostgresMetadataStore extends MetadataStore {
  final Connection _conn;

  PostgresMetadataStore(this._conn);

  @override
  Future<int> runMigrations() async {
    // Ensure schema_migrations table exists
    await _conn.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version VARCHAR(255) PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    ''');

    // Get applied migrations
    final result = await _conn.execute('SELECT version FROM schema_migrations');
    final applied = result.map((row) => row[0] as String).toSet();

    // Run pending migrations
    final pending = _postgresMigrations.entries
        .where((e) => !applied.contains(e.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    var count = 0;
    for (final migration in pending) {
      Logger.info('Applying migration',
          component: 'database', metadata: {'migration': migration.key});
      await _conn.runTx((session) async {
        final statements = _splitStatements(migration.value);
        for (final statement in statements) {
          if (statement.trim().isNotEmpty) {
            await session.execute(statement);
          }
        }
        await session.execute(
          Sql.named(
              'INSERT INTO schema_migrations (version) VALUES (@version)'),
          parameters: {'version': migration.key},
        );
      });
      count++;
    }
    return count;
  }

  @override
  Future<void> dropAllTables() async {
    await _conn.execute('''
      DO \$\$
      DECLARE
          r RECORD;
      BEGIN
          FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public')
          LOOP
              EXECUTE 'DROP TABLE IF EXISTS ' || quote_ident(r.tablename) || ' CASCADE';
          END LOOP;
      END \$\$;
    ''');
  }

  @override
  Future<void> close() async {
    await _conn.close();
  }

  @override
  Future<Map<String, dynamic>> healthCheck() async {
    try {
      // Test basic query with timing
      final startTime = DateTime.now();
      final result = await _conn.execute('SELECT COUNT(*) FROM packages');
      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;

      final packageCount = result.first[0] as int;

      // Get database size
      final sizeResult =
          await _conn.execute('SELECT pg_database_size(current_database())');
      final dbSizeBytes = sizeResult.first[0] as int;

      return {
        'status': 'healthy',
        'type': 'postgresql',
        'latencyMs': latencyMs,
        'packageCount': packageCount,
        'dbSizeBytes': dbSizeBytes,
      };
    } catch (e) {
      return {
        'status': 'unhealthy',
        'type': 'postgresql',
        'error': e.toString(),
      };
    }
  }

  @override
  Future<Package?> getPackage(String name) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT name, owner_id, created_at, updated_at, is_discontinued, replaced_by, is_upstream_cache
        FROM packages WHERE name = @name
      '''),
      parameters: {'name': name},
    );

    if (result.isEmpty) return null;

    final row = result.first;
    return Package(
      name: row[0] as String,
      ownerId: row[1] as String?,
      createdAt: row[2] as DateTime,
      updatedAt: row[3] as DateTime,
      isDiscontinued: row[4] as bool,
      replacedBy: row[5] as String?,
      isUpstreamCache: row[6] as bool,
    );
  }

  @override
  Future<List<PackageVersion>> getPackageVersions(String packageName) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT package_name, version, pubspec_json, archive_key, archive_sha256, published_at,
               is_retracted, retracted_at, retraction_message
        FROM package_versions
        WHERE package_name = @name
        ORDER BY published_at DESC
      '''),
      parameters: {'name': packageName},
    );

    return result.map((row) {
      final pubspecJson = row[2];
      final pubspec = pubspecJson is Map<String, dynamic>
          ? pubspecJson
          : jsonDecode(pubspecJson as String) as Map<String, dynamic>;

      return PackageVersion(
        packageName: row[0] as String,
        version: row[1] as String,
        pubspec: pubspec,
        archiveKey: row[3] as String,
        archiveSha256: row[4] as String,
        publishedAt: row[5] as DateTime,
        isRetracted: row[6] as bool? ?? false,
        retractedAt: row[7] as DateTime?,
        retractionMessage: row[8] as String?,
      );
    }).toList();
  }

  @override
  Future<PackageInfo?> getPackageInfo(String name) async {
    final package = await getPackage(name);
    if (package == null) return null;

    final versions = await getPackageVersions(name);
    return PackageInfo(package: package, versions: versions);
  }

  @override
  Future<PackageVersion?> getPackageVersion(
    String packageName,
    String version,
  ) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT package_name, version, pubspec_json, archive_key, archive_sha256, published_at,
               is_retracted, retracted_at, retraction_message
        FROM package_versions
        WHERE package_name = @name AND version = @version
      '''),
      parameters: {'name': packageName, 'version': version},
    );

    if (result.isEmpty) return null;

    final row = result.first;
    final pubspecJson = row[2];
    final pubspec = pubspecJson is Map<String, dynamic>
        ? pubspecJson
        : jsonDecode(pubspecJson as String) as Map<String, dynamic>;

    return PackageVersion(
      packageName: row[0] as String,
      version: row[1] as String,
      pubspec: pubspec,
      archiveKey: row[3] as String,
      archiveSha256: row[4] as String,
      publishedAt: row[5] as DateTime,
      isRetracted: row[6] as bool? ?? false,
      retractedAt: row[7] as DateTime?,
      retractionMessage: row[8] as String?,
    );
  }

  @override
  Future<void> upsertPackageVersion({
    required String packageName,
    required String version,
    required Map<String, dynamic> pubspec,
    required String archiveKey,
    required String archiveSha256,
    bool isUpstreamCache = false,
    String? ownerId,
  }) async {
    await _conn.runTx((session) async {
      await session.execute(
        Sql.named('''
          INSERT INTO packages (name, owner_id, created_at, updated_at, is_upstream_cache)
          VALUES (@name, @owner_id, NOW(), NOW(), @is_upstream_cache)
          ON CONFLICT (name) DO UPDATE SET updated_at = NOW()
        '''),
        parameters: {
          'name': packageName,
          'owner_id': ownerId,
          'is_upstream_cache': isUpstreamCache,
        },
      );

      await session.execute(
        Sql.named('''
          INSERT INTO package_versions
            (package_name, version, pubspec_json, archive_key, archive_sha256, published_at)
          VALUES (@name, @version, @pubspec, @archive_key, @sha256, NOW())
          ON CONFLICT (package_name, version) DO NOTHING
        '''),
        parameters: {
          'name': packageName,
          'version': version,
          'pubspec': jsonEncode(pubspec),
          'archive_key': archiveKey,
          'sha256': archiveSha256,
        },
      );
    });
  }

  @override
  Future<bool> versionExists(String packageName, String version) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT 1 FROM package_versions
        WHERE package_name = @name AND version = @version
      '''),
      parameters: {'name': packageName, 'version': version},
    );
    return result.isNotEmpty;
  }

  @override
  Future<PackageListResult> listPackages({int page = 1, int limit = 20}) async {
    // Get total count (only local packages, exclude cached)
    final countResult = await _conn.execute(
        'SELECT COUNT(*) FROM packages WHERE is_upstream_cache = false');
    final total = countResult.first[0] as int;

    // Get packages for this page (only local packages)
    final offset = (page - 1) * limit;
    final result = await _conn.execute(
      Sql.named('''
        SELECT name FROM packages
        WHERE is_upstream_cache = false
        ORDER BY updated_at DESC
        LIMIT @limit OFFSET @offset
      '''),
      parameters: {'limit': limit, 'offset': offset},
    );

    final packages = <PackageInfo>[];
    for (final row in result) {
      final name = row[0] as String;
      final info = await getPackageInfo(name);
      if (info != null) {
        packages.add(info);
      }
    }

    return PackageListResult(
      packages: packages,
      total: total,
      page: page,
      limit: limit,
    );
  }

  @override
  Future<PackageListResult> searchPackages(String query,
      {int page = 1, int limit = 20}) async {
    final searchTerm = '%${query.toLowerCase()}%';

    // Get total count (only local packages, exclude cached, match name only)
    final countResult = await _conn.execute(
      Sql.named('''
        SELECT COUNT(*) FROM packages
        WHERE is_upstream_cache = false
          AND LOWER(name) LIKE @search
      '''),
      parameters: {'search': searchTerm},
    );
    final total = countResult.first[0] as int;

    // Get packages for this page (only local packages, match name only)
    final offset = (page - 1) * limit;
    final result = await _conn.execute(
      Sql.named('''
        SELECT name FROM packages
        WHERE is_upstream_cache = false
          AND LOWER(name) LIKE @search
        ORDER BY name
        LIMIT @limit OFFSET @offset
      '''),
      parameters: {'search': searchTerm, 'limit': limit, 'offset': offset},
    );

    final packages = <PackageInfo>[];
    for (final row in result) {
      final name = row[0] as String;
      final info = await getPackageInfo(name);
      if (info != null) {
        packages.add(info);
      }
    }

    return PackageListResult(
      packages: packages,
      total: total,
      page: page,
      limit: limit,
    );
  }

  @override
  Future<AuthToken?> getTokenByHash(String tokenHash) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT token_hash, user_id, label, scopes, created_at, last_used_at, expires_at
        FROM auth_tokens WHERE token_hash = @hash
      '''),
      parameters: {'hash': tokenHash},
    );

    if (result.isEmpty) return null;

    final row = result.first;
    final scopesRaw = row[3];
    final scopes = scopesRaw is List
        ? scopesRaw.cast<String>()
        : <String>[]; // Empty list for null/missing scopes

    return AuthToken(
      tokenHash: row[0] as String,
      userId: row[1] as String? ?? User.anonymousId,
      label: row[2] as String,
      scopes: scopes,
      createdAt: row[4] as DateTime,
      lastUsedAt: row[5] as DateTime?,
      expiresAt: row[6] as DateTime?,
    );
  }

  @override
  Future<void> touchToken(String tokenHash) async {
    await _conn.execute(
      Sql.named('''
        UPDATE auth_tokens SET last_used_at = NOW()
        WHERE token_hash = @hash
      '''),
      parameters: {'hash': tokenHash},
    );
  }

  @override
  Future<String> createToken({
    required String userId,
    required String label,
    List<String>? scopes,
    DateTime? expiresAt,
  }) async {
    final token = MetadataStore._uuid.v4() + MetadataStore._uuid.v4();
    final tokenHash = sha256.convert(utf8.encode(token)).toString();
    final scopesArray = scopes ?? <String>[];

    await _conn.execute(
      Sql.named('''
        INSERT INTO auth_tokens (token_hash, user_id, label, scopes, expires_at)
        VALUES (@hash, @userId, @label, @scopes, @expiresAt)
      '''),
      parameters: {
        'hash': tokenHash,
        'userId': userId,
        'label': label,
        'scopes': scopesArray,
        'expiresAt': expiresAt,
      },
    );

    return token;
  }

  @override
  Future<List<AuthToken>> listTokens({String? userId}) async {
    final sql = userId != null
        ? '''
          SELECT token_hash, user_id, label, scopes, created_at, last_used_at, expires_at
          FROM auth_tokens WHERE user_id = @userId ORDER BY created_at DESC
        '''
        : '''
          SELECT token_hash, user_id, label, scopes, created_at, last_used_at, expires_at
          FROM auth_tokens ORDER BY created_at DESC
        ''';

    final result = await _conn.execute(
      Sql.named(sql),
      parameters: userId != null ? {'userId': userId} : {},
    );

    return result.map((row) {
      final scopesRaw = row[3];
      final scopes = scopesRaw is List ? scopesRaw.cast<String>() : <String>[];

      return AuthToken(
        tokenHash: row[0] as String,
        userId: row[1] as String? ?? User.anonymousId,
        label: row[2] as String,
        scopes: scopes,
        createdAt: row[4] as DateTime,
        lastUsedAt: row[5] as DateTime?,
        expiresAt: row[6] as DateTime?,
      );
    }).toList();
  }

  @override
  Future<bool> deleteToken(String label) async {
    final result = await _conn.execute(
      Sql.named('DELETE FROM auth_tokens WHERE label = @label'),
      parameters: {'label': label},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<UploadSession> createUploadSession({
    Duration ttl = const Duration(hours: 1),
  }) async {
    final id = MetadataStore._uuid.v4();
    final now = DateTime.now();
    final expiresAt = now.add(ttl);

    await _conn.execute(
      Sql.named('''
        INSERT INTO upload_sessions (id, created_at, expires_at)
        VALUES (@id, @created, @expires)
      '''),
      parameters: {
        'id': id,
        'created': now,
        'expires': expiresAt,
      },
    );

    return UploadSession(id: id, createdAt: now, expiresAt: expiresAt);
  }

  @override
  Future<UploadSession?> getUploadSession(String id) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT id, created_at, expires_at
        FROM upload_sessions
        WHERE id = @id AND completed = FALSE
      '''),
      parameters: {'id': id},
    );

    if (result.isEmpty) return null;

    final row = result.first;
    return UploadSession(
      id: row[0] as String,
      createdAt: row[1] as DateTime,
      expiresAt: row[2] as DateTime,
    );
  }

  @override
  Future<void> completeUploadSession(String id) async {
    await _conn.execute(
      Sql.named('UPDATE upload_sessions SET completed = TRUE WHERE id = @id'),
      parameters: {'id': id},
    );
  }

  @override
  Future<int> cleanupExpiredSessions() async {
    final result = await _conn.execute(
      'DELETE FROM upload_sessions WHERE expires_at < NOW()',
    );
    return result.affectedRows;
  }

  // ============ Admin Operations ============

  @override
  Future<PackageListResult> listPackagesByType({
    required bool isUpstreamCache,
    int page = 1,
    int limit = 20,
  }) async {
    // Get total count
    final countResult = await _conn.execute(
      Sql.named(
          'SELECT COUNT(*) FROM packages WHERE is_upstream_cache = @cache'),
      parameters: {'cache': isUpstreamCache},
    );
    final total = countResult.first[0] as int;

    // Get packages for this page
    final offset = (page - 1) * limit;
    final result = await _conn.execute(
      Sql.named('''
        SELECT name FROM packages
        WHERE is_upstream_cache = @cache
        ORDER BY updated_at DESC
        LIMIT @limit OFFSET @offset
      '''),
      parameters: {'cache': isUpstreamCache, 'limit': limit, 'offset': offset},
    );

    final packages = <PackageInfo>[];
    for (final row in result) {
      final name = row[0] as String;
      final info = await getPackageInfo(name);
      if (info != null) {
        packages.add(info);
      }
    }

    return PackageListResult(
      packages: packages,
      total: total,
      page: page,
      limit: limit,
    );
  }

  @override
  Future<int> deletePackage(String name) async {
    // Get version count first
    final countResult = await _conn.execute(
      Sql.named(
          'SELECT COUNT(*) FROM package_versions WHERE package_name = @name'),
      parameters: {'name': name},
    );
    final versionCount = countResult.first[0] as int;

    // Delete package (cascade will delete versions)
    await _conn.execute(
      Sql.named('DELETE FROM packages WHERE name = @name'),
      parameters: {'name': name},
    );

    return versionCount;
  }

  @override
  Future<bool> deletePackageVersion(String name, String version) async {
    final result = await _conn.execute(
      Sql.named('''
        DELETE FROM package_versions
        WHERE package_name = @name AND version = @version
      '''),
      parameters: {'name': name, 'version': version},
    );

    // Check if package has no versions left
    final remaining = await _conn.execute(
      Sql.named(
          'SELECT COUNT(*) FROM package_versions WHERE package_name = @name'),
      parameters: {'name': name},
    );
    if ((remaining.first[0] as int) == 0) {
      await _conn.execute(
        Sql.named('DELETE FROM packages WHERE name = @name'),
        parameters: {'name': name},
      );
    }

    return result.affectedRows > 0;
  }

  @override
  Future<bool> retractPackageVersion(
    String name,
    String version, {
    String? message,
  }) async {
    final result = await _conn.execute(
      Sql.named('''
        UPDATE package_versions
        SET is_retracted = TRUE, retracted_at = NOW(), retraction_message = @message
        WHERE package_name = @name AND version = @version
      '''),
      parameters: {'name': name, 'version': version, 'message': message},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<bool> unretractPackageVersion(String name, String version) async {
    final result = await _conn.execute(
      Sql.named('''
        UPDATE package_versions
        SET is_retracted = FALSE, retracted_at = NULL, retraction_message = NULL
        WHERE package_name = @name AND version = @version
      '''),
      parameters: {'name': name, 'version': version},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<bool> discontinuePackage(String name, {String? replacedBy}) async {
    final result = await _conn.execute(
      Sql.named('''
        UPDATE packages
        SET is_discontinued = TRUE, replaced_by = @replaced
        WHERE name = @name
      '''),
      parameters: {'name': name, 'replaced': replacedBy},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<bool> transferPackageOwnership(
    String packageName,
    String newOwnerId,
  ) async {
    // Check if new owner exists (unless it's the anonymous user)
    if (newOwnerId != User.anonymousId) {
      final userExists = await getUser(newOwnerId);
      if (userExists == null) return false;
    }

    // Transfer ownership
    final result = await _conn.execute(
      Sql.named('''
        UPDATE packages
        SET owner_id = @newOwner, updated_at = NOW()
        WHERE name = @name
      '''),
      parameters: {'name': packageName, 'newOwner': newOwnerId},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<int> clearAllCachedPackages() async {
    // Get count first
    final countResult = await _conn.execute(
      'SELECT COUNT(*) FROM packages WHERE is_upstream_cache = TRUE',
    );
    final count = countResult.first[0] as int;

    // Delete all cached packages (cascade will delete versions)
    await _conn.execute(
      'DELETE FROM packages WHERE is_upstream_cache = TRUE',
    );

    return count;
  }

  @override
  Future<AdminStats> getAdminStats() async {
    final results = await Future.wait([
      _conn.execute('SELECT COUNT(*) FROM packages'),
      _conn.execute(
          'SELECT COUNT(*) FROM packages WHERE is_upstream_cache = FALSE'),
      _conn.execute(
          'SELECT COUNT(*) FROM packages WHERE is_upstream_cache = TRUE'),
      _conn.execute('SELECT COUNT(*) FROM package_versions'),
      _conn.execute('SELECT COUNT(*) FROM users'),
      _conn.execute(
          'SELECT COUNT(*) FROM auth_tokens WHERE expires_at IS NULL OR expires_at > NOW()'),
      _conn.execute('SELECT COUNT(*) FROM package_downloads'),
    ]);

    return AdminStats(
      totalPackages: results[0].first[0] as int,
      localPackages: results[1].first[0] as int,
      cachedPackages: results[2].first[0] as int,
      totalVersions: results[3].first[0] as int,
      totalUsers: results[4].first[0] as int,
      activeTokens: results[5].first[0] as int,
      totalDownloads: (results[6].first[0] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<int> countUsers() async {
    final result = await _conn.execute('SELECT COUNT(*) FROM users');
    return result.first[0] as int;
  }

  @override
  Future<int> countActiveTokens() async {
    final result = await _conn.execute(
        'SELECT COUNT(*) FROM auth_tokens WHERE expires_at IS NULL OR expires_at > NOW()');
    return result.first[0] as int;
  }

  @override
  Future<int> getTotalDownloads() async {
    final result =
        await _conn.execute('SELECT COUNT(*) FROM package_downloads');
    return result.first[0] as int;
  }

  @override
  Future<void> logDownload({
    required String packageName,
    required String version,
    String? ipAddress,
    String? userAgent,
  }) async {
    await _conn.execute(
      Sql.named('''
        INSERT INTO package_downloads (package_name, version, ip_address, user_agent)
        VALUES (@packageName, @version, @ipAddress, @userAgent)
      '''),
      parameters: {
        'packageName': packageName,
        'version': version,
        'ipAddress': ipAddress,
        'userAgent': userAgent,
      },
    );
  }

  @override
  Future<Map<String, int>> getPackagesCreatedPerDay(int days) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT
          DATE(created_at) as date,
          COUNT(*) as count
        FROM packages
        WHERE created_at >= NOW() - INTERVAL '@days days'
        GROUP BY DATE(created_at)
        ORDER BY date DESC
      '''),
      parameters: {'days': days.toString()},
    );

    return {
      for (final row in result) row[0].toString(): row[1] as int,
    };
  }

  @override
  Future<Map<String, int>> getDownloadsPerHour(int hours) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT
          DATE_TRUNC('hour', downloaded_at) as hour,
          COUNT(*) as count
        FROM package_downloads
        WHERE downloaded_at >= NOW() - INTERVAL '@hours hours'
        GROUP BY DATE_TRUNC('hour', downloaded_at)
        ORDER BY hour DESC
      '''),
      parameters: {'hours': hours.toString()},
    );

    return {
      for (final row in result) row[0].toString(): row[1] as int,
    };
  }

  @override
  Future<PackageDownloadStats> getPackageDownloadStats(String packageName,
      {int historyDays = 30}) async {
    // Get total downloads
    final totalResult = await _conn.execute(
      Sql.named('''
        SELECT COUNT(*) FROM package_downloads WHERE package_name = @name
      '''),
      parameters: {'name': packageName},
    );
    final totalDownloads = totalResult.first[0] as int;

    // Get downloads by version
    final versionResult = await _conn.execute(
      Sql.named('''
        SELECT version, COUNT(*) as count
        FROM package_downloads
        WHERE package_name = @name
        GROUP BY version
        ORDER BY count DESC
      '''),
      parameters: {'name': packageName},
    );
    final downloadsByVersion = <String, int>{
      for (final row in versionResult) row[0] as String: row[1] as int,
    };

    // Get daily downloads for the last N days
    final dailyResult = await _conn.execute(
      Sql.named('''
        SELECT DATE(downloaded_at) as day, COUNT(*) as count
        FROM package_downloads
        WHERE package_name = @name
          AND downloaded_at >= NOW() - INTERVAL '@days days'
        GROUP BY DATE(downloaded_at)
        ORDER BY day DESC
      '''),
      parameters: {'name': packageName, 'days': historyDays.toString()},
    );
    final dailyDownloads = <String, int>{
      for (final row in dailyResult)
        row[0].toString().split(' ')[0]: row[1] as int,
    };

    return PackageDownloadStats(
      packageName: packageName,
      totalDownloads: totalDownloads,
      downloadsByVersion: downloadsByVersion,
      dailyDownloads: dailyDownloads,
    );
  }

  @override
  Future<List<String>> getPackageArchiveKeys(String name) async {
    final result = await _conn.execute(
      Sql.named(
          'SELECT archive_key FROM package_versions WHERE package_name = @name'),
      parameters: {'name': name},
    );
    return result.map((row) => row[0] as String).toList();
  }

  @override
  Future<String?> getVersionArchiveKey(String name, String version) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT archive_key FROM package_versions
        WHERE package_name = @name AND version = @version
      '''),
      parameters: {'name': name, 'version': version},
    );
    if (result.isEmpty) return null;
    return result.first[0] as String;
  }

  // ============ Users ============

  @override
  Future<String> createUser({
    required String email,
    String? passwordHash,
    String? name,
  }) async {
    final id = MetadataStore._uuid.v4();
    await _conn.execute(
      Sql.named('''
        INSERT INTO users (id, email, password_hash, name)
        VALUES (@id, @email, @passwordHash, @name)
      '''),
      parameters: {
        'id': id,
        'email': email,
        'passwordHash': passwordHash,
        'name': name,
      },
    );
    return id;
  }

  @override
  Future<User?> getUser(String id) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT id, email, password_hash, name, is_active, created_at, last_login_at
        FROM users WHERE id = @id
      '''),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return User(
      id: row[0] as String,
      email: row[1] as String,
      passwordHash: row[2] as String?,
      name: row[3] as String?,
      isActive: row[4] as bool,
      createdAt: row[5] as DateTime,
      lastLoginAt: row[6] as DateTime?,
    );
  }

  @override
  Future<User?> getUserByEmail(String email) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT id, email, password_hash, name, is_active, created_at, last_login_at
        FROM users WHERE email = @email
      '''),
      parameters: {'email': email},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return User(
      id: row[0] as String,
      email: row[1] as String,
      passwordHash: row[2] as String?,
      name: row[3] as String?,
      isActive: row[4] as bool,
      createdAt: row[5] as DateTime,
      lastLoginAt: row[6] as DateTime?,
    );
  }

  @override
  Future<bool> updateUser(String id,
      {String? name, String? passwordHash, bool? isActive}) async {
    final updates = <String>[];
    final params = <String, Object?>{'id': id};
    if (name != null) {
      updates.add('name = @name');
      params['name'] = name;
    }
    if (passwordHash != null) {
      updates.add('password_hash = @passwordHash');
      params['passwordHash'] = passwordHash;
    }
    if (isActive != null) {
      updates.add('is_active = @isActive');
      params['isActive'] = isActive;
    }
    if (updates.isEmpty) return false;

    final result = await _conn.execute(
      Sql.named('UPDATE users SET ${updates.join(', ')} WHERE id = @id'),
      parameters: params,
    );
    return result.affectedRows > 0;
  }

  @override
  Future<void> touchUserLogin(String id) async {
    await _conn.execute(
      Sql.named('UPDATE users SET last_login_at = NOW() WHERE id = @id'),
      parameters: {'id': id},
    );
  }

  @override
  Future<bool> deleteUser(String id) async {
    // Transfer packages to anonymous before deleting
    await _conn.execute(
      Sql.named('UPDATE packages SET owner_id = @anon WHERE owner_id = @id'),
      parameters: {'id': id, 'anon': User.anonymousId},
    );
    // Transfer tokens to anonymous
    await _conn.execute(
      Sql.named('UPDATE auth_tokens SET user_id = @anon WHERE user_id = @id'),
      parameters: {'id': id, 'anon': User.anonymousId},
    );
    // Delete user sessions
    await _conn.execute(
      Sql.named('DELETE FROM user_sessions WHERE user_id = @id'),
      parameters: {'id': id},
    );
    // Delete user
    final result = await _conn.execute(
      Sql.named('DELETE FROM users WHERE id = @id'),
      parameters: {'id': id},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<List<User>> listUsers({int page = 1, int limit = 20}) async {
    final offset = (page - 1) * limit;
    final result = await _conn.execute(
      Sql.named('''
        SELECT id, email, password_hash, name, is_active, created_at, last_login_at
        FROM users ORDER BY created_at DESC
        LIMIT @limit OFFSET @offset
      '''),
      parameters: {'limit': limit, 'offset': offset},
    );
    return result
        .map((row) => User(
              id: row[0] as String,
              email: row[1] as String,
              passwordHash: row[2] as String?,
              name: row[3] as String?,
              isActive: row[4] as bool,
              createdAt: row[5] as DateTime,
              lastLoginAt: row[6] as DateTime?,
            ))
        .toList();
  }

  // ============ Site Config ============

  @override
  Future<SiteConfig?> getConfig(String name) async {
    final result = await _conn.execute(
      Sql.named(
          'SELECT name, value_type, value, description FROM site_config WHERE name = @name'),
      parameters: {'name': name},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return SiteConfig(
      name: row[0] as String,
      valueType: ConfigValueType.values.firstWhere(
        (t) => t.name == row[1],
        orElse: () => ConfigValueType.string,
      ),
      value: row[2] as String,
      description: row[3] as String?,
    );
  }

  @override
  Future<void> setConfig(String name, String value) async {
    await _conn.execute(
      Sql.named('''
        UPDATE site_config SET value = @value WHERE name = @name
      '''),
      parameters: {'name': name, 'value': value},
    );
  }

  @override
  Future<List<SiteConfig>> getAllConfig() async {
    final result = await _conn.execute(
      'SELECT name, value_type, value, description FROM site_config ORDER BY name',
    );
    return result
        .map((row) => SiteConfig(
              name: row[0] as String,
              valueType: ConfigValueType.values.firstWhere(
                (t) => t.name == row[1],
                orElse: () => ConfigValueType.string,
              ),
              value: row[2] as String,
              description: row[3] as String?,
            ))
        .toList();
  }

  // ============ User Sessions ============

  @override
  Future<UserSession> createUserSession({
    required String userId,
    Duration ttl = const Duration(hours: 24),
  }) async {
    final sessionId = sha256
        .convert(
            utf8.encode(MetadataStore._uuid.v4() + MetadataStore._uuid.v4()))
        .toString();
    final now = DateTime.now();
    final expiresAt = now.add(ttl);

    await _conn.execute(
      Sql.named('''
        INSERT INTO user_sessions (session_id, user_id, created_at, expires_at, session_type)
        VALUES (@sessionId, @userId, @createdAt, @expiresAt, 'user')
      '''),
      parameters: {
        'sessionId': sessionId,
        'userId': userId,
        'createdAt': now,
        'expiresAt': expiresAt,
      },
    );

    return UserSession(
      sessionId: sessionId,
      userId: userId,
      createdAt: now,
      expiresAt: expiresAt,
      type: SessionType.user,
    );
  }

  @override
  Future<UserSession?> getUserSession(String sessionId) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT session_id, user_id, created_at, expires_at, session_type
        FROM user_sessions WHERE session_id = @sessionId
      '''),
      parameters: {'sessionId': sessionId},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return UserSession(
      sessionId: row[0] as String,
      userId: row[1] as String,
      createdAt: row[2] as DateTime,
      expiresAt: row[3] as DateTime,
      type: SessionType.fromString(row[4] as String),
    );
  }

  @override
  Future<bool> deleteUserSession(String sessionId) async {
    final result = await _conn.execute(
      Sql.named('DELETE FROM user_sessions WHERE session_id = @sessionId'),
      parameters: {'sessionId': sessionId},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<int> cleanupExpiredUserSessions() async {
    final result = await _conn.execute(
      'DELETE FROM user_sessions WHERE expires_at < NOW()',
    );
    return result.affectedRows;
  }

  // ============ Admin Users ============

  @override
  Future<String> createAdminUser({
    required String username,
    required String passwordHash,
    String? name,
    bool mustChangePassword = false,
  }) async {
    final id = MetadataStore._uuid.v4();
    await _conn.execute(
      Sql.named('''
        INSERT INTO admin_users (id, username, password_hash, name, must_change_password)
        VALUES (@id, @username, @passwordHash, @name, @mustChangePassword)
      '''),
      parameters: {
        'id': id,
        'username': username,
        'passwordHash': passwordHash,
        'name': name,
        'mustChangePassword': mustChangePassword,
      },
    );
    return id;
  }

  @override
  Future<AdminUser?> getAdminUser(String id) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT id, username, password_hash, name, is_active, must_change_password, created_at, last_login_at
        FROM admin_users WHERE id = @id
      '''),
      parameters: {'id': id},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return AdminUser(
      id: row[0] as String,
      username: row[1] as String,
      passwordHash: row[2] as String?,
      name: row[3] as String?,
      isActive: row[4] as bool,
      mustChangePassword: row[5] as bool? ?? false,
      createdAt: row[6] as DateTime,
      lastLoginAt: row[7] as DateTime?,
    );
  }

  @override
  Future<AdminUser?> getAdminUserByUsername(String username) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT id, username, password_hash, name, is_active, must_change_password, created_at, last_login_at
        FROM admin_users WHERE username = @username
      '''),
      parameters: {'username': username},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return AdminUser(
      id: row[0] as String,
      username: row[1] as String,
      passwordHash: row[2] as String?,
      name: row[3] as String?,
      isActive: row[4] as bool,
      mustChangePassword: row[5] as bool? ?? false,
      createdAt: row[6] as DateTime,
      lastLoginAt: row[7] as DateTime?,
    );
  }

  @override
  Future<bool> updateAdminUser(String id,
      {String? name,
      String? passwordHash,
      bool? isActive,
      bool? mustChangePassword}) async {
    final updates = <String>[];
    final params = <String, Object?>{'id': id};
    if (name != null) {
      updates.add('name = @name');
      params['name'] = name;
    }
    if (passwordHash != null) {
      updates.add('password_hash = @passwordHash');
      params['passwordHash'] = passwordHash;
    }
    if (isActive != null) {
      updates.add('is_active = @isActive');
      params['isActive'] = isActive;
    }
    if (mustChangePassword != null) {
      updates.add('must_change_password = @mustChangePassword');
      params['mustChangePassword'] = mustChangePassword;
    }
    if (updates.isEmpty) return false;

    final result = await _conn.execute(
      Sql.named('UPDATE admin_users SET ${updates.join(', ')} WHERE id = @id'),
      parameters: params,
    );
    return result.affectedRows > 0;
  }

  @override
  Future<void> touchAdminLogin(String id) async {
    await _conn.execute(
      Sql.named('UPDATE admin_users SET last_login_at = NOW() WHERE id = @id'),
      parameters: {'id': id},
    );
  }

  @override
  Future<bool> deleteAdminUser(String id) async {
    // Delete admin sessions
    await _conn.execute(
      Sql.named(
          "DELETE FROM user_sessions WHERE user_id = @id AND session_type = 'admin'"),
      parameters: {'id': id},
    );
    // Delete admin user
    final result = await _conn.execute(
      Sql.named('DELETE FROM admin_users WHERE id = @id'),
      parameters: {'id': id},
    );
    return result.affectedRows > 0;
  }

  @override
  Future<List<AdminUser>> listAdminUsers({int page = 1, int limit = 20}) async {
    final offset = (page - 1) * limit;
    final result = await _conn.execute(
      Sql.named('''
        SELECT id, username, password_hash, name, is_active, must_change_password, created_at, last_login_at
        FROM admin_users ORDER BY created_at DESC
        LIMIT @limit OFFSET @offset
      '''),
      parameters: {'limit': limit, 'offset': offset},
    );
    return result
        .map((row) => AdminUser(
              id: row[0] as String,
              username: row[1] as String,
              passwordHash: row[2] as String?,
              name: row[3] as String?,
              isActive: row[4] as bool,
              mustChangePassword: row[5] as bool? ?? false,
              createdAt: row[6] as DateTime,
              lastLoginAt: row[7] as DateTime?,
            ))
        .toList();
  }

  @override
  Future<bool> ensureDefaultAdminUser(
      String Function(String) hashPassword) async {
    // Check if any admin users exist
    final result = await _conn.execute(
      Sql.named('SELECT COUNT(*) FROM admin_users'),
    );
    final count = result.first[0] as int;
    if (count > 0) return false;

    // Create default admin user with must_change_password=true
    await createAdminUser(
      username: 'admin',
      passwordHash: hashPassword('admin'),
      name: 'Default Admin',
      mustChangePassword: true,
    );
    return true;
  }

  // ============ Admin Sessions ============

  @override
  Future<UserSession> createAdminSession({
    required String adminUserId,
    Duration ttl = const Duration(hours: 8),
  }) async {
    final sessionId = sha256
        .convert(
            utf8.encode(MetadataStore._uuid.v4() + MetadataStore._uuid.v4()))
        .toString();
    final now = DateTime.now();
    final expiresAt = now.add(ttl);

    await _conn.execute(
      Sql.named('''
        INSERT INTO user_sessions (session_id, user_id, created_at, expires_at, session_type)
        VALUES (@sessionId, @userId, @createdAt, @expiresAt, 'admin')
      '''),
      parameters: {
        'sessionId': sessionId,
        'userId': adminUserId,
        'createdAt': now,
        'expiresAt': expiresAt,
      },
    );

    return UserSession(
      sessionId: sessionId,
      userId: adminUserId,
      createdAt: now,
      expiresAt: expiresAt,
      type: SessionType.admin,
    );
  }

  @override
  Future<UserSession?> getAdminSession(String sessionId) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT session_id, user_id, created_at, expires_at, session_type
        FROM user_sessions WHERE session_id = @sessionId AND session_type = 'admin'
      '''),
      parameters: {'sessionId': sessionId},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return UserSession(
      sessionId: row[0] as String,
      userId: row[1] as String,
      createdAt: row[2] as DateTime,
      expiresAt: row[3] as DateTime,
      type: SessionType.fromString(row[4] as String),
    );
  }

  @override
  Future<bool> deleteAdminSession(String sessionId) async {
    final result = await _conn.execute(
      Sql.named(
          "DELETE FROM user_sessions WHERE session_id = @sessionId AND session_type = 'admin'"),
      parameters: {'sessionId': sessionId},
    );
    return result.affectedRows > 0;
  }

  // ============ Admin Login History ============

  @override
  Future<String> logAdminLogin({
    required String adminUserId,
    String? ipAddress,
    String? userAgent,
    bool success = true,
  }) async {
    final id = MetadataStore._uuid.v4();
    await _conn.execute(
      Sql.named('''
        INSERT INTO admin_login_history (id, admin_user_id, ip_address, user_agent, success)
        VALUES (@id, @adminUserId, @ipAddress, @userAgent, @success)
      '''),
      parameters: {
        'id': id,
        'adminUserId': adminUserId,
        'ipAddress': ipAddress,
        'userAgent': userAgent,
        'success': success,
      },
    );
    return id;
  }

  @override
  Future<List<AdminLoginHistory>> getAdminLoginHistory({
    required String adminUserId,
    int limit = 50,
  }) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT id, admin_user_id, login_at, ip_address, user_agent, success
        FROM admin_login_history
        WHERE admin_user_id = @adminUserId
        ORDER BY login_at DESC
        LIMIT @limit
      '''),
      parameters: {'adminUserId': adminUserId, 'limit': limit},
    );

    return result
        .map((row) => AdminLoginHistory(
              id: row[0] as String,
              adminUserId: row[1] as String,
              loginAt: row[2] as DateTime,
              ipAddress: row[3] as String?,
              userAgent: row[4] as String?,
              success: row[5] as bool,
            ))
        .toList();
  }

  @override
  Future<List<AdminLoginHistory>> getRecentAdminLogins({
    int limit = 100,
  }) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT id, admin_user_id, login_at, ip_address, user_agent, success
        FROM admin_login_history
        ORDER BY login_at DESC
        LIMIT @limit
      '''),
      parameters: {'limit': limit},
    );

    return result
        .map((row) => AdminLoginHistory(
              id: row[0] as String,
              adminUserId: row[1] as String,
              loginAt: row[2] as DateTime,
              ipAddress: row[3] as String?,
              userAgent: row[4] as String?,
              success: row[5] as bool,
            ))
        .toList();
  }

  @override
  Future<String> logActivity({
    required String activityType,
    required String actorType,
    String? actorId,
    String? actorEmail,
    String? actorUsername,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? metadata,
    String? ipAddress,
  }) async {
    final id = MetadataStore._uuid.v4();
    await _conn.execute(
      Sql.named('''
        INSERT INTO activity_log (
          id, activity_type, actor_type, actor_id, actor_email, actor_username,
          target_type, target_id, metadata, ip_address
        ) VALUES (
          @id, @activityType, @actorType, @actorId, @actorEmail, @actorUsername,
          @targetType, @targetId, @metadata, @ipAddress
        )
      '''),
      parameters: {
        'id': id,
        'activityType': activityType,
        'actorType': actorType,
        'actorId': actorId,
        'actorEmail': actorEmail,
        'actorUsername': actorUsername,
        'targetType': targetType,
        'targetId': targetId,
        'metadata': metadata != null ? jsonEncode(metadata) : null,
        'ipAddress': ipAddress,
      },
    );
    return id;
  }

  @override
  Future<List<ActivityLog>> getRecentActivity({
    int limit = 10,
    String? activityType,
    String? actorType,
  }) async {
    final whereConditions = <String>[];
    final parameters = <String, dynamic>{'limit': limit};

    if (activityType != null) {
      whereConditions.add('activity_type = @activityType');
      parameters['activityType'] = activityType;
    }
    if (actorType != null) {
      whereConditions.add('actor_type = @actorType');
      parameters['actorType'] = actorType;
    }

    final whereClause = whereConditions.isNotEmpty
        ? 'WHERE ${whereConditions.join(' AND ')}'
        : '';

    final result = await _conn.execute(
      Sql.named('''
        SELECT
          id, timestamp, activity_type, actor_type, actor_id, actor_email,
          actor_username, target_type, target_id, metadata, ip_address
        FROM activity_log
        $whereClause
        ORDER BY timestamp DESC
        LIMIT @limit
      '''),
      parameters: parameters,
    );

    return result.map((row) {
      return ActivityLog.fromRow({
        'id': row[0] as String,
        'timestamp': row[1] as DateTime,
        'activity_type': row[2] as String,
        'actor_type': row[3] as String,
        'actor_id': row[4] as String?,
        'actor_email': row[5] as String?,
        'actor_username': row[6] as String?,
        'target_type': row[7] as String?,
        'target_id': row[8] as String?,
        'metadata': row[9] as String?,
        'ip_address': row[10] as String?,
      });
    }).toList();
  }

  // ============ Webhook Operations ============

  @override
  Future<Webhook> createWebhook({
    required String url,
    String? secret,
    required List<String> events,
  }) async {
    final id = MetadataStore._uuid.v4();
    await _conn.execute(
      Sql.named('''
        INSERT INTO webhooks (id, url, secret, events)
        VALUES (@id, @url, @secret, @events)
      '''),
      parameters: {
        'id': id,
        'url': url,
        'secret': secret,
        'events': events,
      },
    );

    return Webhook(
      id: id,
      url: url,
      secret: secret,
      events: events,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<Webhook?> getWebhook(String id) async {
    final result = await _conn.execute(
      Sql.named('SELECT * FROM webhooks WHERE id = @id'),
      parameters: {'id': id},
    );

    if (result.isEmpty) return null;
    final row = result.first;
    return _webhookFromRow(row);
  }

  @override
  Future<List<Webhook>> listWebhooks({bool activeOnly = false}) async {
    final query = activeOnly
        ? 'SELECT * FROM webhooks WHERE is_active = true ORDER BY created_at DESC'
        : 'SELECT * FROM webhooks ORDER BY created_at DESC';

    final result = await _conn.execute(query);
    return result.map(_webhookFromRow).toList();
  }

  @override
  Future<void> updateWebhook(Webhook webhook) async {
    await _conn.execute(
      Sql.named('''
        UPDATE webhooks
        SET url = @url, secret = @secret, events = @events, is_active = @isActive,
            last_triggered_at = @lastTriggeredAt, failure_count = @failureCount
        WHERE id = @id
      '''),
      parameters: {
        'id': webhook.id,
        'url': webhook.url,
        'secret': webhook.secret,
        'events': webhook.events,
        'isActive': webhook.isActive,
        'lastTriggeredAt': webhook.lastTriggeredAt,
        'failureCount': webhook.failureCount,
      },
    );
  }

  @override
  Future<void> deleteWebhook(String id) async {
    await _conn.execute(
      Sql.named('DELETE FROM webhooks WHERE id = @id'),
      parameters: {'id': id},
    );
  }

  @override
  Future<List<Webhook>> getWebhooksForEvent(String eventType) async {
    // Get webhooks that are active and match the event type or have '*' (all events)
    final result = await _conn.execute(
      Sql.named('''
        SELECT * FROM webhooks
        WHERE is_active = true
          AND (@eventType = ANY(events) OR '*' = ANY(events))
        ORDER BY created_at
      '''),
      parameters: {'eventType': eventType},
    );
    return result.map(_webhookFromRow).toList();
  }

  @override
  Future<void> logWebhookDelivery(WebhookDelivery delivery) async {
    await _conn.execute(
      Sql.named('''
        INSERT INTO webhook_deliveries
          (id, webhook_id, event_type, payload, status_code, success, error, duration_ms, delivered_at)
        VALUES
          (@id, @webhookId, @eventType, @payload, @statusCode, @success, @error, @durationMs, @deliveredAt)
      '''),
      parameters: {
        'id': delivery.id,
        'webhookId': delivery.webhookId,
        'eventType': delivery.eventType,
        'payload': jsonEncode(delivery.payload),
        'statusCode': delivery.statusCode,
        'success': delivery.success,
        'error': delivery.error,
        'durationMs': delivery.duration.inMilliseconds,
        'deliveredAt': delivery.deliveredAt,
      },
    );
  }

  @override
  Future<List<WebhookDelivery>> getWebhookDeliveries(
    String webhookId, {
    int limit = 20,
  }) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT * FROM webhook_deliveries
        WHERE webhook_id = @webhookId
        ORDER BY delivered_at DESC
        LIMIT @limit
      '''),
      parameters: {'webhookId': webhookId, 'limit': limit},
    );

    return result.map((row) => _webhookDeliveryFromRow(row)).toList();
  }

  Webhook _webhookFromRow(ResultRow row) {
    final map = row.toColumnMap();
    return Webhook(
      id: map['id'] as String,
      url: map['url'] as String,
      secret: map['secret'] as String?,
      events: (map['events'] as List).cast<String>(),
      isActive: map['is_active'] as bool,
      createdAt: map['created_at'] as DateTime,
      lastTriggeredAt: map['last_triggered_at'] as DateTime?,
      failureCount: map['failure_count'] as int,
    );
  }

  WebhookDelivery _webhookDeliveryFromRow(ResultRow row) {
    final map = row.toColumnMap();
    return WebhookDelivery(
      id: map['id'] as String,
      webhookId: map['webhook_id'] as String,
      eventType: map['event_type'] as String,
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      statusCode: map['status_code'] as int,
      success: map['success'] as bool,
      error: map['error'] as String?,
      duration: Duration(milliseconds: map['duration_ms'] as int),
      deliveredAt: map['delivered_at'] as DateTime,
    );
  }

  // ============ Backup Export Methods ============

  /// Export all packages for backup.
  Future<List<Map<String, dynamic>>> exportPackages() async {
    final result = await _conn.execute('SELECT * FROM packages');
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Export all package versions for backup.
  Future<List<Map<String, dynamic>>> exportPackageVersions() async {
    final result = await _conn.execute('SELECT * FROM package_versions');
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Export all users for backup.
  Future<List<Map<String, dynamic>>> exportUsers() async {
    final result = await _conn.execute('SELECT * FROM users');
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Export all admin users for backup.
  Future<List<Map<String, dynamic>>> exportAdminUsers() async {
    final result = await _conn.execute('SELECT * FROM admin_users');
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Export all auth tokens for backup.
  Future<List<Map<String, dynamic>>> exportAuthTokens() async {
    final result = await _conn.execute('SELECT * FROM auth_tokens');
    return result.map((row) => row.toColumnMap()).toList();
  }

  /// Export all activity log for backup.
  Future<List<Map<String, dynamic>>> exportActivityLog() async {
    final result = await _conn.execute('SELECT * FROM activity_log');
    return result.map((row) => row.toColumnMap()).toList();
  }

  // ============ Backup Import Methods ============

  /// Import packages from backup.
  Future<void> importPackages(List<Map<String, dynamic>> packages) async {
    for (final pkg in packages) {
      await _conn.execute(
        Sql.named('''
          INSERT INTO packages (name, created_at, updated_at, is_discontinued, replaced_by, is_upstream_cache, owner_id)
          VALUES (@name, @created_at, @updated_at, @is_discontinued, @replaced_by, @is_upstream_cache, @owner_id)
          ON CONFLICT (name) DO UPDATE SET
            created_at = EXCLUDED.created_at,
            updated_at = EXCLUDED.updated_at,
            is_discontinued = EXCLUDED.is_discontinued,
            replaced_by = EXCLUDED.replaced_by,
            is_upstream_cache = EXCLUDED.is_upstream_cache,
            owner_id = EXCLUDED.owner_id
        '''),
        parameters: {
          'name': pkg['name'],
          'created_at': pkg['created_at'],
          'updated_at': pkg['updated_at'],
          'is_discontinued': pkg['is_discontinued'],
          'replaced_by': pkg['replaced_by'],
          'is_upstream_cache': pkg['is_upstream_cache'],
          'owner_id': pkg['owner_id'],
        },
      );
    }
  }

  /// Import package versions from backup.
  Future<void> importPackageVersions(
      List<Map<String, dynamic>> versions) async {
    for (final v in versions) {
      await _conn.execute(
        Sql.named('''
          INSERT INTO package_versions (id, package_name, version, pubspec_json, archive_key, archive_sha256, published_at)
          VALUES (@id, @package_name, @version, @pubspec_json, @archive_key, @archive_sha256, @published_at)
          ON CONFLICT (package_name, version) DO UPDATE SET
            pubspec_json = EXCLUDED.pubspec_json,
            archive_key = EXCLUDED.archive_key,
            archive_sha256 = EXCLUDED.archive_sha256,
            published_at = EXCLUDED.published_at
        '''),
        parameters: {
          'id': v['id'],
          'package_name': v['package_name'],
          'version': v['version'],
          'pubspec_json': v['pubspec_json'],
          'archive_key': v['archive_key'],
          'archive_sha256': v['archive_sha256'],
          'published_at': v['published_at'],
        },
      );
    }
  }

  /// Import users from backup.
  Future<void> importUsers(List<Map<String, dynamic>> users) async {
    for (final u in users) {
      await _conn.execute(
        Sql.named('''
          INSERT INTO users (id, email, password_hash, name, is_active, created_at, last_login_at)
          VALUES (@id, @email, @password_hash, @name, @is_active, @created_at, @last_login_at)
          ON CONFLICT (id) DO UPDATE SET
            email = EXCLUDED.email,
            password_hash = EXCLUDED.password_hash,
            name = EXCLUDED.name,
            is_active = EXCLUDED.is_active,
            created_at = EXCLUDED.created_at,
            last_login_at = EXCLUDED.last_login_at
        '''),
        parameters: {
          'id': u['id'],
          'email': u['email'],
          'password_hash': u['password_hash'],
          'name': u['name'],
          'is_active': u['is_active'],
          'created_at': u['created_at'],
          'last_login_at': u['last_login_at'],
        },
      );
    }
  }

  /// Import admin users from backup.
  Future<void> importAdminUsers(List<Map<String, dynamic>> adminUsers) async {
    for (final a in adminUsers) {
      await _conn.execute(
        Sql.named('''
          INSERT INTO admin_users (id, username, password_hash, name, is_active, created_at, last_login_at, must_change_password)
          VALUES (@id, @username, @password_hash, @name, @is_active, @created_at, @last_login_at, @must_change_password)
          ON CONFLICT (id) DO UPDATE SET
            username = EXCLUDED.username,
            password_hash = EXCLUDED.password_hash,
            name = EXCLUDED.name,
            is_active = EXCLUDED.is_active,
            created_at = EXCLUDED.created_at,
            last_login_at = EXCLUDED.last_login_at,
            must_change_password = EXCLUDED.must_change_password
        '''),
        parameters: {
          'id': a['id'],
          'username': a['username'],
          'password_hash': a['password_hash'],
          'name': a['name'],
          'is_active': a['is_active'],
          'created_at': a['created_at'],
          'last_login_at': a['last_login_at'],
          'must_change_password': a['must_change_password'],
        },
      );
    }
  }

  /// Import auth tokens from backup.
  Future<void> importAuthTokens(List<Map<String, dynamic>> tokens) async {
    for (final t in tokens) {
      await _conn.execute(
        Sql.named('''
          INSERT INTO auth_tokens (token_hash, label, scopes, created_at, last_used_at, user_id, expires_at)
          VALUES (@token_hash, @label, @scopes, @created_at, @last_used_at, @user_id, @expires_at)
          ON CONFLICT (token_hash) DO UPDATE SET
            label = EXCLUDED.label,
            scopes = EXCLUDED.scopes,
            created_at = EXCLUDED.created_at,
            last_used_at = EXCLUDED.last_used_at,
            user_id = EXCLUDED.user_id,
            expires_at = EXCLUDED.expires_at
        '''),
        parameters: {
          'token_hash': t['token_hash'],
          'label': t['label'],
          'scopes': t['scopes'],
          'created_at': t['created_at'],
          'last_used_at': t['last_used_at'],
          'user_id': t['user_id'],
          'expires_at': t['expires_at'],
        },
      );
    }
  }

  /// Import activity log from backup.
  Future<void> importActivityLog(List<Map<String, dynamic>> activities) async {
    for (final a in activities) {
      await _conn.execute(
        Sql.named('''
          INSERT INTO activity_log (id, timestamp, activity_type, actor_type, actor_id, actor_email,
            actor_username, target_type, target_id, metadata, ip_address)
          VALUES (@id, @timestamp, @activity_type, @actor_type, @actor_id, @actor_email,
            @actor_username, @target_type, @target_id, @metadata, @ip_address)
          ON CONFLICT (id) DO NOTHING
        '''),
        parameters: {
          'id': a['id'],
          'timestamp': a['timestamp'],
          'activity_type': a['activity_type'],
          'actor_type': a['actor_type'],
          'actor_id': a['actor_id'],
          'actor_email': a['actor_email'],
          'actor_username': a['actor_username'],
          'target_type': a['target_type'],
          'target_id': a['target_id'],
          'metadata': a['metadata'],
          'ip_address': a['ip_address'],
        },
      );
    }
  }
}

/// Metadata storage backed by SQLite.
class SqliteMetadataStore extends MetadataStore {
  final Database _db;

  SqliteMetadataStore._(this._db);

  /// Open or create a SQLite database.
  static SqliteMetadataStore open(String path) {
    // Ensure directory exists
    final dir = Directory(p.dirname(path));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final db = sqlite3.open(path);

    // Enable WAL mode for better concurrent read/write performance
    // WAL allows concurrent readers while a write is in progress
    db.execute('PRAGMA journal_mode = WAL');
    db.execute('PRAGMA synchronous = NORMAL');
    db.execute('PRAGMA busy_timeout = 5000');

    return SqliteMetadataStore._(db);
  }

  /// Create an in-memory SQLite database for testing.
  factory SqliteMetadataStore.inMemory() {
    final db = sqlite3.openInMemory();
    return SqliteMetadataStore._(db);
  }

  @override
  Future<int> runMigrations() async {
    // Ensure schema_migrations table exists
    _db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version TEXT PRIMARY KEY,
        applied_at TEXT NOT NULL DEFAULT (datetime('now'))
      )
    ''');

    // Get applied migrations
    final result = _db.select('SELECT version FROM schema_migrations');
    final applied = result.map((row) => row['version'] as String).toSet();

    // Run pending migrations
    final pending = _sqliteMigrations.entries
        .where((e) => !applied.contains(e.key))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    var count = 0;
    for (final migration in pending) {
      Logger.info('Applying migration',
          component: 'database', metadata: {'migration': migration.key});
      _db.execute('BEGIN TRANSACTION');
      try {
        final statements = _splitStatements(migration.value);
        for (final statement in statements) {
          if (statement.trim().isNotEmpty) {
            _db.execute(statement);
          }
        }
        _db.execute(
          'INSERT INTO schema_migrations (version) VALUES (?)',
          [migration.key],
        );
        _db.execute('COMMIT');
        count++;
      } catch (e) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
    return count;
  }

  @override
  Future<void> dropAllTables() async {
    // Get all table names except sqlite internal tables
    final result = _db.select('''
      SELECT name FROM sqlite_master
      WHERE type='table' AND name NOT LIKE 'sqlite_%'
    ''');

    // Drop each table
    for (final row in result) {
      final tableName = row['name'] as String;
      _db.execute('DROP TABLE IF EXISTS $tableName');
    }
  }

  @override
  Future<void> close() async {
    _db.dispose();
  }

  @override
  Future<Map<String, dynamic>> healthCheck() async {
    try {
      // Test basic query
      final startTime = DateTime.now();
      final result = _db.select('SELECT COUNT(*) as count FROM packages');
      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;

      final packageCount = result.first['count'] as int;

      // Get database file size
      final dbPath = _db.select('PRAGMA database_list').first['file'] as String;
      final dbFile = File(dbPath);
      final dbSizeBytes = dbFile.existsSync() ? dbFile.lengthSync() : 0;

      return {
        'status': 'healthy',
        'type': 'sqlite',
        'latencyMs': latencyMs,
        'packageCount': packageCount,
        'dbSizeBytes': dbSizeBytes,
      };
    } catch (e) {
      return {
        'status': 'unhealthy',
        'type': 'sqlite',
        'error': e.toString(),
      };
    }
  }

  @override
  Future<Package?> getPackage(String name) async {
    final result = _db.select('''
      SELECT name, owner_id, created_at, updated_at, is_discontinued, replaced_by, is_upstream_cache
      FROM packages WHERE name = ?
    ''', [name]);

    if (result.isEmpty) return null;

    final row = result.first;
    return Package(
      name: row['name'] as String,
      ownerId: row['owner_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      isDiscontinued: (row['is_discontinued'] as int) == 1,
      replacedBy: row['replaced_by'] as String?,
      isUpstreamCache: (row['is_upstream_cache'] as int) == 1,
    );
  }

  @override
  Future<List<PackageVersion>> getPackageVersions(String packageName) async {
    final result = _db.select('''
      SELECT package_name, version, pubspec_json, archive_key, archive_sha256, published_at,
             is_retracted, retracted_at, retraction_message
      FROM package_versions
      WHERE package_name = ?
      ORDER BY published_at DESC
    ''', [packageName]);

    return result.map((row) {
      final pubspec =
          jsonDecode(row['pubspec_json'] as String) as Map<String, dynamic>;

      return PackageVersion(
        packageName: row['package_name'] as String,
        version: row['version'] as String,
        pubspec: pubspec,
        archiveKey: row['archive_key'] as String,
        archiveSha256: row['archive_sha256'] as String,
        publishedAt: DateTime.parse(row['published_at'] as String),
        isRetracted: (row['is_retracted'] as int?) == 1,
        retractedAt: row['retracted_at'] != null
            ? DateTime.parse(row['retracted_at'] as String)
            : null,
        retractionMessage: row['retraction_message'] as String?,
      );
    }).toList();
  }

  @override
  Future<PackageInfo?> getPackageInfo(String name) async {
    final package = await getPackage(name);
    if (package == null) return null;

    final versions = await getPackageVersions(name);
    return PackageInfo(package: package, versions: versions);
  }

  @override
  Future<PackageVersion?> getPackageVersion(
    String packageName,
    String version,
  ) async {
    final result = _db.select('''
      SELECT package_name, version, pubspec_json, archive_key, archive_sha256, published_at,
             is_retracted, retracted_at, retraction_message
      FROM package_versions
      WHERE package_name = ? AND version = ?
    ''', [packageName, version]);

    if (result.isEmpty) return null;

    final row = result.first;
    final pubspec =
        jsonDecode(row['pubspec_json'] as String) as Map<String, dynamic>;

    return PackageVersion(
      packageName: row['package_name'] as String,
      version: row['version'] as String,
      pubspec: pubspec,
      archiveKey: row['archive_key'] as String,
      archiveSha256: row['archive_sha256'] as String,
      publishedAt: DateTime.parse(row['published_at'] as String),
      isRetracted: (row['is_retracted'] as int?) == 1,
      retractedAt: row['retracted_at'] != null
          ? DateTime.parse(row['retracted_at'] as String)
          : null,
      retractionMessage: row['retraction_message'] as String?,
    );
  }

  @override
  Future<void> upsertPackageVersion({
    required String packageName,
    required String version,
    required Map<String, dynamic> pubspec,
    required String archiveKey,
    required String archiveSha256,
    bool isUpstreamCache = false,
    String? ownerId,
  }) async {
    final now = DateTime.now().toIso8601String();

    _db.execute('BEGIN TRANSACTION');
    try {
      _db.execute('''
        INSERT INTO packages (name, owner_id, created_at, updated_at, is_upstream_cache)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT (name) DO UPDATE SET updated_at = ?
      ''', [packageName, ownerId, now, now, isUpstreamCache ? 1 : 0, now]);

      _db.execute('''
        INSERT INTO package_versions
          (package_name, version, pubspec_json, archive_key, archive_sha256, published_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (package_name, version) DO NOTHING
      ''', [
        packageName,
        version,
        jsonEncode(pubspec),
        archiveKey,
        archiveSha256,
        now,
      ]);

      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  Future<bool> versionExists(String packageName, String version) async {
    final result = _db.select('''
      SELECT 1 FROM package_versions
      WHERE package_name = ? AND version = ?
    ''', [packageName, version]);
    return result.isNotEmpty;
  }

  @override
  Future<PackageListResult> listPackages({int page = 1, int limit = 20}) async {
    // Get total count (only local packages, exclude cached)
    final countResult =
        _db.select('SELECT COUNT(*) FROM packages WHERE is_upstream_cache = 0');
    final total = countResult.first.values.first as int;

    // Get packages for this page (only local packages)
    final offset = (page - 1) * limit;
    final result = _db.select('''
      SELECT name FROM packages
      WHERE is_upstream_cache = 0
      ORDER BY updated_at DESC
      LIMIT ? OFFSET ?
    ''', [limit, offset]);

    final packages = <PackageInfo>[];
    for (final row in result) {
      final name = row['name'] as String;
      final info = await getPackageInfo(name);
      if (info != null) {
        packages.add(info);
      }
    }

    return PackageListResult(
      packages: packages,
      total: total,
      page: page,
      limit: limit,
    );
  }

  @override
  Future<PackageListResult> searchPackages(String query,
      {int page = 1, int limit = 20}) async {
    final searchTerm = '%${query.toLowerCase()}%';

    // Get total count (only local packages, exclude cached, match name only)
    final countResult = _db.select('''
      SELECT COUNT(*) FROM packages
      WHERE is_upstream_cache = 0
        AND LOWER(name) LIKE ?
    ''', [searchTerm]);
    final total = countResult.first.values.first as int;

    // Get packages for this page (only local packages, match name only)
    final offset = (page - 1) * limit;
    final result = _db.select('''
      SELECT name FROM packages
      WHERE is_upstream_cache = 0
        AND LOWER(name) LIKE ?
      ORDER BY name
      LIMIT ? OFFSET ?
    ''', [searchTerm, limit, offset]);

    final packages = <PackageInfo>[];
    for (final row in result) {
      final name = row['name'] as String;
      final info = await getPackageInfo(name);
      if (info != null) {
        packages.add(info);
      }
    }

    return PackageListResult(
      packages: packages,
      total: total,
      page: page,
      limit: limit,
    );
  }

  @override
  Future<AuthToken?> getTokenByHash(String tokenHash) async {
    final result = _db.select('''
      SELECT token_hash, user_id, label, scopes, created_at, last_used_at, expires_at
      FROM auth_tokens WHERE token_hash = ?
    ''', [tokenHash]);

    if (result.isEmpty) return null;

    final row = result.first;
    final scopesJson = row['scopes'] as String?;
    final scopes = scopesJson != null && scopesJson.isNotEmpty
        ? (jsonDecode(scopesJson) as List).cast<String>()
        : <String>[];

    return AuthToken(
      tokenHash: row['token_hash'] as String,
      userId: row['user_id'] as String? ?? User.anonymousId,
      label: row['label'] as String,
      scopes: scopes,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastUsedAt: row['last_used_at'] != null
          ? DateTime.parse(row['last_used_at'] as String)
          : null,
      expiresAt: row['expires_at'] != null
          ? DateTime.parse(row['expires_at'] as String)
          : null,
    );
  }

  @override
  Future<void> touchToken(String tokenHash) async {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      UPDATE auth_tokens SET last_used_at = ?
      WHERE token_hash = ?
    ''', [now, tokenHash]);
  }

  @override
  Future<String> createToken({
    required String userId,
    required String label,
    List<String>? scopes,
    DateTime? expiresAt,
  }) async {
    final token = MetadataStore._uuid.v4() + MetadataStore._uuid.v4();
    final tokenHash = sha256.convert(utf8.encode(token)).toString();
    final now = DateTime.now().toIso8601String();
    final scopesJson = jsonEncode(scopes ?? []);

    _db.execute('''
      INSERT INTO auth_tokens (token_hash, user_id, label, scopes, created_at, expires_at)
      VALUES (?, ?, ?, ?, ?, ?)
    ''', [
      tokenHash,
      userId,
      label,
      scopesJson,
      now,
      expiresAt?.toIso8601String()
    ]);

    return token;
  }

  @override
  Future<List<AuthToken>> listTokens({String? userId}) async {
    final sql = userId != null
        ? '''
          SELECT token_hash, user_id, label, scopes, created_at, last_used_at, expires_at
          FROM auth_tokens WHERE user_id = ? ORDER BY created_at DESC
        '''
        : '''
          SELECT token_hash, user_id, label, scopes, created_at, last_used_at, expires_at
          FROM auth_tokens ORDER BY created_at DESC
        ''';

    final result = _db.select(sql, userId != null ? [userId] : []);

    return result.map((row) {
      final scopesJson = row['scopes'] as String?;
      final scopes = scopesJson != null && scopesJson.isNotEmpty
          ? (jsonDecode(scopesJson) as List).cast<String>()
          : <String>[];

      return AuthToken(
        tokenHash: row['token_hash'] as String,
        userId: row['user_id'] as String? ?? User.anonymousId,
        label: row['label'] as String,
        scopes: scopes,
        createdAt: DateTime.parse(row['created_at'] as String),
        lastUsedAt: row['last_used_at'] != null
            ? DateTime.parse(row['last_used_at'] as String)
            : null,
        expiresAt: row['expires_at'] != null
            ? DateTime.parse(row['expires_at'] as String)
            : null,
      );
    }).toList();
  }

  @override
  Future<bool> deleteToken(String label) async {
    _db.execute('DELETE FROM auth_tokens WHERE label = ?', [label]);
    return _db.updatedRows > 0;
  }

  @override
  Future<UploadSession> createUploadSession({
    Duration ttl = const Duration(hours: 1),
  }) async {
    final id = MetadataStore._uuid.v4();
    final now = DateTime.now();
    final expiresAt = now.add(ttl);

    _db.execute('''
      INSERT INTO upload_sessions (id, created_at, expires_at)
      VALUES (?, ?, ?)
    ''', [id, now.toIso8601String(), expiresAt.toIso8601String()]);

    return UploadSession(id: id, createdAt: now, expiresAt: expiresAt);
  }

  @override
  Future<UploadSession?> getUploadSession(String id) async {
    final result = _db.select('''
      SELECT id, created_at, expires_at
      FROM upload_sessions
      WHERE id = ? AND completed = 0
    ''', [id]);

    if (result.isEmpty) return null;

    final row = result.first;
    return UploadSession(
      id: row['id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      expiresAt: DateTime.parse(row['expires_at'] as String),
    );
  }

  @override
  Future<void> completeUploadSession(String id) async {
    _db.execute('UPDATE upload_sessions SET completed = 1 WHERE id = ?', [id]);
  }

  @override
  Future<int> cleanupExpiredSessions() async {
    final now = DateTime.now().toIso8601String();
    _db.execute('DELETE FROM upload_sessions WHERE expires_at < ?', [now]);
    return _db.updatedRows;
  }

  // ============ Admin Operations ============

  @override
  Future<PackageListResult> listPackagesByType({
    required bool isUpstreamCache,
    int page = 1,
    int limit = 20,
  }) async {
    // Get total count
    final cacheValue = isUpstreamCache ? 1 : 0;
    final countResult = _db.select(
      'SELECT COUNT(*) FROM packages WHERE is_upstream_cache = ?',
      [cacheValue],
    );
    final total = countResult.first.values.first as int;

    // Get packages for this page
    final offset = (page - 1) * limit;
    final result = _db.select('''
      SELECT name FROM packages
      WHERE is_upstream_cache = ?
      ORDER BY updated_at DESC
      LIMIT ? OFFSET ?
    ''', [cacheValue, limit, offset]);

    final packages = <PackageInfo>[];
    for (final row in result) {
      final name = row['name'] as String;
      final info = await getPackageInfo(name);
      if (info != null) {
        packages.add(info);
      }
    }

    return PackageListResult(
      packages: packages,
      total: total,
      page: page,
      limit: limit,
    );
  }

  @override
  Future<int> deletePackage(String name) async {
    // Get version count first
    final countResult = _db.select(
      'SELECT COUNT(*) FROM package_versions WHERE package_name = ?',
      [name],
    );
    final versionCount = countResult.first.values.first as int;

    // Delete package (cascade will delete versions)
    _db.execute('DELETE FROM packages WHERE name = ?', [name]);

    return versionCount;
  }

  @override
  Future<bool> deletePackageVersion(String name, String version) async {
    _db.execute('''
      DELETE FROM package_versions
      WHERE package_name = ? AND version = ?
    ''', [name, version]);
    final deleted = _db.updatedRows > 0;

    // Check if package has no versions left
    final remaining = _db.select(
      'SELECT COUNT(*) FROM package_versions WHERE package_name = ?',
      [name],
    );
    if ((remaining.first.values.first as int) == 0) {
      _db.execute('DELETE FROM packages WHERE name = ?', [name]);
    }

    return deleted;
  }

  @override
  Future<bool> retractPackageVersion(
    String name,
    String version, {
    String? message,
  }) async {
    _db.execute('''
      UPDATE package_versions
      SET is_retracted = 1, retracted_at = datetime('now'), retraction_message = ?
      WHERE package_name = ? AND version = ?
    ''', [message, name, version]);
    return _db.updatedRows > 0;
  }

  @override
  Future<bool> unretractPackageVersion(String name, String version) async {
    _db.execute('''
      UPDATE package_versions
      SET is_retracted = 0, retracted_at = NULL, retraction_message = NULL
      WHERE package_name = ? AND version = ?
    ''', [name, version]);
    return _db.updatedRows > 0;
  }

  @override
  Future<bool> discontinuePackage(String name, {String? replacedBy}) async {
    _db.execute('''
      UPDATE packages
      SET is_discontinued = 1, replaced_by = ?
      WHERE name = ?
    ''', [replacedBy, name]);
    return _db.updatedRows > 0;
  }

  @override
  Future<bool> transferPackageOwnership(
    String packageName,
    String newOwnerId,
  ) async {
    // Check if new owner exists (unless it's the anonymous user)
    if (newOwnerId != User.anonymousId) {
      final userExists = await getUser(newOwnerId);
      if (userExists == null) return false;
    }

    // Transfer ownership
    _db.execute('''
      UPDATE packages
      SET owner_id = ?, updated_at = datetime('now')
      WHERE name = ?
    ''', [newOwnerId, packageName]);
    return _db.updatedRows > 0;
  }

  @override
  Future<int> clearAllCachedPackages() async {
    // Get count first
    final countResult = _db.select(
      'SELECT COUNT(*) FROM packages WHERE is_upstream_cache = 1',
    );
    final count = countResult.first.values.first as int;

    // Delete all cached packages (cascade will delete versions)
    _db.execute('DELETE FROM packages WHERE is_upstream_cache = 1');

    return count;
  }

  @override
  Future<AdminStats> getAdminStats() async {
    final totalResult = _db.select('SELECT COUNT(*) FROM packages');
    final localResult = _db.select(
      'SELECT COUNT(*) FROM packages WHERE is_upstream_cache = 0',
    );
    final cachedResult = _db.select(
      'SELECT COUNT(*) FROM packages WHERE is_upstream_cache = 1',
    );
    final versionsResult = _db.select('SELECT COUNT(*) FROM package_versions');
    final usersResult = _db.select('SELECT COUNT(*) FROM users');
    final tokensResult = _db.select(
      "SELECT COUNT(*) FROM auth_tokens WHERE expires_at IS NULL OR expires_at > datetime('now')",
    );
    final downloadsResult = _db.select(
      'SELECT COUNT(*) FROM package_downloads',
    );

    return AdminStats(
      totalPackages: totalResult.first.values.first as int,
      localPackages: localResult.first.values.first as int,
      cachedPackages: cachedResult.first.values.first as int,
      totalVersions: versionsResult.first.values.first as int,
      totalUsers: usersResult.first.values.first as int,
      activeTokens: tokensResult.first.values.first as int,
      totalDownloads:
          (downloadsResult.first.values.first as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<int> countUsers() async {
    final result = _db.select('SELECT COUNT(*) as count FROM users');
    return result.first['count'] as int;
  }

  @override
  Future<int> countActiveTokens() async {
    final now = DateTime.now().toIso8601String();
    final result = _db.select(
      'SELECT COUNT(*) as count FROM auth_tokens WHERE expires_at IS NULL OR expires_at > ?',
      [now],
    );
    return result.first['count'] as int;
  }

  @override
  Future<int> getTotalDownloads() async {
    final result =
        _db.select('SELECT COUNT(*) as count FROM package_downloads');
    return result.first['count'] as int;
  }

  @override
  Future<void> logDownload({
    required String packageName,
    required String version,
    String? ipAddress,
    String? userAgent,
  }) async {
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO package_downloads (package_name, version, downloaded_at, ip_address, user_agent)
      VALUES (?, ?, ?, ?, ?)
    ''', [packageName, version, now, ipAddress, userAgent]);
  }

  @override
  Future<Map<String, int>> getPackagesCreatedPerDay(int days) async {
    final cutoffDate =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    final result = _db.select('''
      SELECT
        DATE(created_at) as date,
        COUNT(*) as count
      FROM packages
      WHERE created_at >= ?
      GROUP BY DATE(created_at)
      ORDER BY date DESC
    ''', [cutoffDate]);

    return {
      for (final row in result) row['date'] as String: row['count'] as int,
    };
  }

  @override
  Future<Map<String, int>> getDownloadsPerHour(int hours) async {
    final cutoffTime =
        DateTime.now().subtract(Duration(hours: hours)).toIso8601String();
    final result = _db.select('''
      SELECT
        STRFTIME('%Y-%m-%d %H:00:00', downloaded_at) as hour,
        COUNT(*) as count
      FROM package_downloads
      WHERE downloaded_at >= ?
      GROUP BY STRFTIME('%Y-%m-%d %H:00:00', downloaded_at)
      ORDER BY hour DESC
    ''', [cutoffTime]);

    return {
      for (final row in result) row['hour'] as String: row['count'] as int,
    };
  }

  @override
  Future<PackageDownloadStats> getPackageDownloadStats(String packageName,
      {int historyDays = 30}) async {
    // Get total downloads
    final totalResult = _db.select(
      'SELECT COUNT(*) as count FROM package_downloads WHERE package_name = ?',
      [packageName],
    );
    final totalDownloads = totalResult.first['count'] as int;

    // Get downloads by version
    final versionResult = _db.select('''
      SELECT version, COUNT(*) as count
      FROM package_downloads
      WHERE package_name = ?
      GROUP BY version
      ORDER BY count DESC
    ''', [packageName]);
    final downloadsByVersion = <String, int>{
      for (final row in versionResult)
        row['version'] as String: row['count'] as int,
    };

    // Get daily downloads for the last N days
    final cutoffDate =
        DateTime.now().subtract(Duration(days: historyDays)).toIso8601String();
    final dailyResult = _db.select('''
      SELECT DATE(downloaded_at) as day, COUNT(*) as count
      FROM package_downloads
      WHERE package_name = ? AND downloaded_at >= ?
      GROUP BY DATE(downloaded_at)
      ORDER BY day DESC
    ''', [packageName, cutoffDate]);
    final dailyDownloads = <String, int>{
      for (final row in dailyResult) row['day'] as String: row['count'] as int,
    };

    return PackageDownloadStats(
      packageName: packageName,
      totalDownloads: totalDownloads,
      downloadsByVersion: downloadsByVersion,
      dailyDownloads: dailyDownloads,
    );
  }

  @override
  Future<List<String>> getPackageArchiveKeys(String name) async {
    final result = _db.select(
      'SELECT archive_key FROM package_versions WHERE package_name = ?',
      [name],
    );
    return result.map((row) => row['archive_key'] as String).toList();
  }

  @override
  Future<String?> getVersionArchiveKey(String name, String version) async {
    final result = _db.select('''
      SELECT archive_key FROM package_versions
      WHERE package_name = ? AND version = ?
    ''', [name, version]);
    if (result.isEmpty) return null;
    return result.first['archive_key'] as String;
  }

  // ============ Users ============

  @override
  Future<String> createUser({
    required String email,
    String? passwordHash,
    String? name,
  }) async {
    final id = MetadataStore._uuid.v4();
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO users (id, email, password_hash, name, created_at)
      VALUES (?, ?, ?, ?, ?)
    ''', [id, email, passwordHash, name, now]);
    return id;
  }

  @override
  Future<User?> getUser(String id) async {
    final result = _db.select('''
      SELECT id, email, password_hash, name, is_active, created_at, last_login_at
      FROM users WHERE id = ?
    ''', [id]);
    if (result.isEmpty) return null;
    final row = result.first;
    return User(
      id: row['id'] as String,
      email: row['email'] as String,
      passwordHash: row['password_hash'] as String?,
      name: row['name'] as String?,
      isActive: (row['is_active'] as int) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastLoginAt: row['last_login_at'] != null
          ? DateTime.parse(row['last_login_at'] as String)
          : null,
    );
  }

  @override
  Future<User?> getUserByEmail(String email) async {
    final result = _db.select('''
      SELECT id, email, password_hash, name, is_active, created_at, last_login_at
      FROM users WHERE email = ?
    ''', [email]);
    if (result.isEmpty) return null;
    final row = result.first;
    return User(
      id: row['id'] as String,
      email: row['email'] as String,
      passwordHash: row['password_hash'] as String?,
      name: row['name'] as String?,
      isActive: (row['is_active'] as int) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastLoginAt: row['last_login_at'] != null
          ? DateTime.parse(row['last_login_at'] as String)
          : null,
    );
  }

  @override
  Future<bool> updateUser(String id,
      {String? name, String? passwordHash, bool? isActive}) async {
    final updates = <String>[];
    final params = <Object?>[];
    if (name != null) {
      updates.add('name = ?');
      params.add(name);
    }
    if (passwordHash != null) {
      updates.add('password_hash = ?');
      params.add(passwordHash);
    }
    if (isActive != null) {
      updates.add('is_active = ?');
      params.add(isActive ? 1 : 0);
    }
    if (updates.isEmpty) return false;

    params.add(id);
    _db.execute('UPDATE users SET ${updates.join(', ')} WHERE id = ?', params);
    return _db.updatedRows > 0;
  }

  @override
  Future<void> touchUserLogin(String id) async {
    final now = DateTime.now().toIso8601String();
    _db.execute('UPDATE users SET last_login_at = ? WHERE id = ?', [now, id]);
  }

  @override
  Future<bool> deleteUser(String id) async {
    // Transfer packages to anonymous before deleting
    _db.execute('UPDATE packages SET owner_id = ? WHERE owner_id = ?',
        [User.anonymousId, id]);
    // Transfer tokens to anonymous
    _db.execute('UPDATE auth_tokens SET user_id = ? WHERE user_id = ?',
        [User.anonymousId, id]);
    // Delete user sessions
    _db.execute('DELETE FROM user_sessions WHERE user_id = ?', [id]);
    // Delete user
    _db.execute('DELETE FROM users WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  @override
  Future<List<User>> listUsers({int page = 1, int limit = 20}) async {
    final offset = (page - 1) * limit;
    final result = _db.select('''
      SELECT id, email, password_hash, name, is_active, created_at, last_login_at
      FROM users ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    ''', [limit, offset]);
    return result
        .map((row) => User(
              id: row['id'] as String,
              email: row['email'] as String,
              passwordHash: row['password_hash'] as String?,
              name: row['name'] as String?,
              isActive: (row['is_active'] as int) == 1,
              createdAt: DateTime.parse(row['created_at'] as String),
              lastLoginAt: row['last_login_at'] != null
                  ? DateTime.parse(row['last_login_at'] as String)
                  : null,
            ))
        .toList();
  }

  // ============ Site Config ============

  @override
  Future<SiteConfig?> getConfig(String name) async {
    final result = _db.select(
      'SELECT name, value_type, value, description FROM site_config WHERE name = ?',
      [name],
    );
    if (result.isEmpty) return null;
    final row = result.first;
    return SiteConfig(
      name: row['name'] as String,
      valueType: ConfigValueType.values.firstWhere(
        (t) => t.name == row['value_type'],
        orElse: () => ConfigValueType.string,
      ),
      value: row['value'] as String,
      description: row['description'] as String?,
    );
  }

  @override
  Future<void> setConfig(String name, String value) async {
    _db.execute(
      'UPDATE site_config SET value = ? WHERE name = ?',
      [value, name],
    );
  }

  @override
  Future<List<SiteConfig>> getAllConfig() async {
    final result = _db.select(
      'SELECT name, value_type, value, description FROM site_config ORDER BY name',
    );
    return result
        .map((row) => SiteConfig(
              name: row['name'] as String,
              valueType: ConfigValueType.values.firstWhere(
                (t) => t.name == row['value_type'],
                orElse: () => ConfigValueType.string,
              ),
              value: row['value'] as String,
              description: row['description'] as String?,
            ))
        .toList();
  }

  // ============ User Sessions ============

  @override
  Future<UserSession> createUserSession({
    required String userId,
    Duration ttl = const Duration(hours: 24),
  }) async {
    final sessionId = sha256
        .convert(
            utf8.encode(MetadataStore._uuid.v4() + MetadataStore._uuid.v4()))
        .toString();
    final now = DateTime.now();
    final expiresAt = now.add(ttl);

    _db.execute('''
      INSERT INTO user_sessions (session_id, user_id, created_at, expires_at, session_type)
      VALUES (?, ?, ?, ?, 'user')
    ''', [
      sessionId,
      userId,
      now.toIso8601String(),
      expiresAt.toIso8601String()
    ]);

    return UserSession(
      sessionId: sessionId,
      userId: userId,
      createdAt: now,
      expiresAt: expiresAt,
      type: SessionType.user,
    );
  }

  @override
  Future<UserSession?> getUserSession(String sessionId) async {
    final result = _db.select('''
      SELECT session_id, user_id, created_at, expires_at, session_type
      FROM user_sessions WHERE session_id = ?
    ''', [sessionId]);
    if (result.isEmpty) return null;
    final row = result.first;
    return UserSession(
      sessionId: row['session_id'] as String,
      userId: row['user_id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      expiresAt: DateTime.parse(row['expires_at'] as String),
      type: SessionType.fromString(row['session_type'] as String),
    );
  }

  @override
  Future<bool> deleteUserSession(String sessionId) async {
    _db.execute('DELETE FROM user_sessions WHERE session_id = ?', [sessionId]);
    return _db.updatedRows > 0;
  }

  @override
  Future<int> cleanupExpiredUserSessions() async {
    final now = DateTime.now().toIso8601String();
    _db.execute('DELETE FROM user_sessions WHERE expires_at < ?', [now]);
    return _db.updatedRows;
  }

  // ============ Admin Users ============

  @override
  Future<String> createAdminUser({
    required String username,
    required String passwordHash,
    String? name,
    bool mustChangePassword = false,
  }) async {
    final id = MetadataStore._uuid.v4();
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO admin_users (id, username, password_hash, name, must_change_password, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    ''', [id, username, passwordHash, name, mustChangePassword ? 1 : 0, now]);
    return id;
  }

  @override
  Future<AdminUser?> getAdminUser(String id) async {
    final result = _db.select('''
      SELECT id, username, password_hash, name, is_active, must_change_password, created_at, last_login_at
      FROM admin_users WHERE id = ?
    ''', [id]);
    if (result.isEmpty) return null;
    final row = result.first;
    return AdminUser(
      id: row['id'] as String,
      username: row['username'] as String,
      passwordHash: row['password_hash'] as String?,
      name: row['name'] as String?,
      isActive: (row['is_active'] as int) == 1,
      mustChangePassword: (row['must_change_password'] as int?) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastLoginAt: row['last_login_at'] != null
          ? DateTime.parse(row['last_login_at'] as String)
          : null,
    );
  }

  @override
  Future<AdminUser?> getAdminUserByUsername(String username) async {
    final result = _db.select('''
      SELECT id, username, password_hash, name, is_active, must_change_password, created_at, last_login_at
      FROM admin_users WHERE username = ?
    ''', [username]);
    if (result.isEmpty) return null;
    final row = result.first;
    return AdminUser(
      id: row['id'] as String,
      username: row['username'] as String,
      passwordHash: row['password_hash'] as String?,
      name: row['name'] as String?,
      isActive: (row['is_active'] as int) == 1,
      mustChangePassword: (row['must_change_password'] as int?) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastLoginAt: row['last_login_at'] != null
          ? DateTime.parse(row['last_login_at'] as String)
          : null,
    );
  }

  @override
  Future<bool> updateAdminUser(String id,
      {String? name,
      String? passwordHash,
      bool? isActive,
      bool? mustChangePassword}) async {
    final updates = <String>[];
    final params = <Object?>[];
    if (name != null) {
      updates.add('name = ?');
      params.add(name);
    }
    if (passwordHash != null) {
      updates.add('password_hash = ?');
      params.add(passwordHash);
    }
    if (isActive != null) {
      updates.add('is_active = ?');
      params.add(isActive ? 1 : 0);
    }
    if (mustChangePassword != null) {
      updates.add('must_change_password = ?');
      params.add(mustChangePassword ? 1 : 0);
    }
    if (updates.isEmpty) return false;

    params.add(id);
    _db.execute(
        'UPDATE admin_users SET ${updates.join(', ')} WHERE id = ?', params);
    return _db.updatedRows > 0;
  }

  @override
  Future<void> touchAdminLogin(String id) async {
    final now = DateTime.now().toIso8601String();
    _db.execute(
        'UPDATE admin_users SET last_login_at = ? WHERE id = ?', [now, id]);
  }

  @override
  Future<bool> deleteAdminUser(String id) async {
    // Delete admin sessions
    _db.execute(
        "DELETE FROM user_sessions WHERE user_id = ? AND session_type = 'admin'",
        [id]);
    // Delete admin user
    _db.execute('DELETE FROM admin_users WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  @override
  Future<List<AdminUser>> listAdminUsers({int page = 1, int limit = 20}) async {
    final offset = (page - 1) * limit;
    final result = _db.select('''
      SELECT id, username, password_hash, name, is_active, must_change_password, created_at, last_login_at
      FROM admin_users ORDER BY created_at DESC
      LIMIT ? OFFSET ?
    ''', [limit, offset]);
    return result
        .map((row) => AdminUser(
              id: row['id'] as String,
              username: row['username'] as String,
              passwordHash: row['password_hash'] as String?,
              name: row['name'] as String?,
              isActive: (row['is_active'] as int) == 1,
              mustChangePassword: (row['must_change_password'] as int?) == 1,
              createdAt: DateTime.parse(row['created_at'] as String),
              lastLoginAt: row['last_login_at'] != null
                  ? DateTime.parse(row['last_login_at'] as String)
                  : null,
            ))
        .toList();
  }

  @override
  Future<bool> ensureDefaultAdminUser(
      String Function(String) hashPassword) async {
    // Check if any admin users exist
    final result = _db.select('SELECT COUNT(*) as count FROM admin_users');
    final count = result.first['count'] as int;
    if (count > 0) return false;

    // Create default admin user with must_change_password=true
    await createAdminUser(
      username: 'admin',
      passwordHash: hashPassword('admin'),
      name: 'Default Admin',
      mustChangePassword: true,
    );
    return true;
  }

  // ============ Admin Sessions ============

  @override
  Future<UserSession> createAdminSession({
    required String adminUserId,
    Duration ttl = const Duration(hours: 8),
  }) async {
    final sessionId = sha256
        .convert(
            utf8.encode(MetadataStore._uuid.v4() + MetadataStore._uuid.v4()))
        .toString();
    final now = DateTime.now();
    final expiresAt = now.add(ttl);

    _db.execute('''
      INSERT INTO user_sessions (session_id, user_id, created_at, expires_at, session_type)
      VALUES (?, ?, ?, ?, 'admin')
    ''', [
      sessionId,
      adminUserId,
      now.toIso8601String(),
      expiresAt.toIso8601String()
    ]);

    return UserSession(
      sessionId: sessionId,
      userId: adminUserId,
      createdAt: now,
      expiresAt: expiresAt,
      type: SessionType.admin,
    );
  }

  @override
  Future<UserSession?> getAdminSession(String sessionId) async {
    final result = _db.select('''
      SELECT session_id, user_id, created_at, expires_at, session_type
      FROM user_sessions WHERE session_id = ? AND session_type = 'admin'
    ''', [sessionId]);
    if (result.isEmpty) return null;
    final row = result.first;
    return UserSession(
      sessionId: row['session_id'] as String,
      userId: row['user_id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      expiresAt: DateTime.parse(row['expires_at'] as String),
      type: SessionType.fromString(row['session_type'] as String),
    );
  }

  @override
  Future<bool> deleteAdminSession(String sessionId) async {
    _db.execute(
        "DELETE FROM user_sessions WHERE session_id = ? AND session_type = 'admin'",
        [sessionId]);
    return _db.updatedRows > 0;
  }

  // ============ Admin Login History ============

  @override
  Future<String> logAdminLogin({
    required String adminUserId,
    String? ipAddress,
    String? userAgent,
    bool success = true,
  }) async {
    final id = MetadataStore._uuid.v4();
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO admin_login_history (id, admin_user_id, login_at, ip_address, user_agent, success)
      VALUES (?, ?, ?, ?, ?, ?)
    ''', [id, adminUserId, now, ipAddress, userAgent, success ? 1 : 0]);
    return id;
  }

  @override
  Future<List<AdminLoginHistory>> getAdminLoginHistory({
    required String adminUserId,
    int limit = 50,
  }) async {
    final result = _db.select('''
      SELECT id, admin_user_id, login_at, ip_address, user_agent, success
      FROM admin_login_history
      WHERE admin_user_id = ?
      ORDER BY login_at DESC
      LIMIT ?
    ''', [adminUserId, limit]);

    return result
        .map((row) => AdminLoginHistory(
              id: row['id'] as String,
              adminUserId: row['admin_user_id'] as String,
              loginAt: DateTime.parse(row['login_at'] as String),
              ipAddress: row['ip_address'] as String?,
              userAgent: row['user_agent'] as String?,
              success: (row['success'] as int) == 1,
            ))
        .toList();
  }

  @override
  Future<List<AdminLoginHistory>> getRecentAdminLogins({
    int limit = 100,
  }) async {
    final result = _db.select('''
      SELECT id, admin_user_id, login_at, ip_address, user_agent, success
      FROM admin_login_history
      ORDER BY login_at DESC
      LIMIT ?
    ''', [limit]);

    return result
        .map((row) => AdminLoginHistory(
              id: row['id'] as String,
              adminUserId: row['admin_user_id'] as String,
              loginAt: DateTime.parse(row['login_at'] as String),
              ipAddress: row['ip_address'] as String?,
              userAgent: row['user_agent'] as String?,
              success: (row['success'] as int) == 1,
            ))
        .toList();
  }

  @override
  Future<String> logActivity({
    required String activityType,
    required String actorType,
    String? actorId,
    String? actorEmail,
    String? actorUsername,
    String? targetType,
    String? targetId,
    Map<String, dynamic>? metadata,
    String? ipAddress,
  }) async {
    final id = MetadataStore._uuid.v4();
    _db.execute('''
      INSERT INTO activity_log (
        id, activity_type, actor_type, actor_id, actor_email, actor_username,
        target_type, target_id, metadata, ip_address
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      id,
      activityType,
      actorType,
      actorId,
      actorEmail,
      actorUsername,
      targetType,
      targetId,
      metadata != null ? jsonEncode(metadata) : null,
      ipAddress,
    ]);
    return id;
  }

  @override
  Future<List<ActivityLog>> getRecentActivity({
    int limit = 10,
    String? activityType,
    String? actorType,
  }) async {
    final whereConditions = <String>[];
    final parameters = <dynamic>[];

    if (activityType != null) {
      whereConditions.add('activity_type = ?');
      parameters.add(activityType);
    }
    if (actorType != null) {
      whereConditions.add('actor_type = ?');
      parameters.add(actorType);
    }

    final whereClause = whereConditions.isNotEmpty
        ? 'WHERE ${whereConditions.join(' AND ')}'
        : '';

    parameters.add(limit);

    final result = _db.select('''
      SELECT
        id, timestamp, activity_type, actor_type, actor_id, actor_email,
        actor_username, target_type, target_id, metadata, ip_address
      FROM activity_log
      $whereClause
      ORDER BY timestamp DESC
      LIMIT ?
    ''', parameters);

    return result.map((row) {
      return ActivityLog.fromRow({
        'id': row['id'] as String,
        'timestamp': DateTime.parse(row['timestamp'] as String),
        'activity_type': row['activity_type'] as String,
        'actor_type': row['actor_type'] as String,
        'actor_id': row['actor_id'] as String?,
        'actor_email': row['actor_email'] as String?,
        'actor_username': row['actor_username'] as String?,
        'target_type': row['target_type'] as String?,
        'target_id': row['target_id'] as String?,
        'metadata': row['metadata'] as String?,
        'ip_address': row['ip_address'] as String?,
      });
    }).toList();
  }

  // ============ Webhook Operations ============

  @override
  Future<Webhook> createWebhook({
    required String url,
    String? secret,
    required List<String> events,
  }) async {
    final id = MetadataStore._uuid.v4();
    final now = DateTime.now().toIso8601String();
    _db.execute('''
      INSERT INTO webhooks (id, url, secret, events, created_at)
      VALUES (?, ?, ?, ?, ?)
    ''', [id, url, secret, events.join(','), now]);

    return Webhook(
      id: id,
      url: url,
      secret: secret,
      events: events,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<Webhook?> getWebhook(String id) async {
    final result = _db.select('SELECT * FROM webhooks WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return _webhookFromRow(result.first);
  }

  @override
  Future<List<Webhook>> listWebhooks({bool activeOnly = false}) async {
    final query = activeOnly
        ? 'SELECT * FROM webhooks WHERE is_active = 1 ORDER BY created_at DESC'
        : 'SELECT * FROM webhooks ORDER BY created_at DESC';

    final result = _db.select(query);
    return result.map(_webhookFromRow).toList();
  }

  @override
  Future<void> updateWebhook(Webhook webhook) async {
    _db.execute('''
      UPDATE webhooks
      SET url = ?, secret = ?, events = ?, is_active = ?,
          last_triggered_at = ?, failure_count = ?
      WHERE id = ?
    ''', [
      webhook.url,
      webhook.secret,
      webhook.events.join(','),
      webhook.isActive ? 1 : 0,
      webhook.lastTriggeredAt?.toIso8601String(),
      webhook.failureCount,
      webhook.id,
    ]);
  }

  @override
  Future<void> deleteWebhook(String id) async {
    _db.execute('DELETE FROM webhooks WHERE id = ?', [id]);
  }

  @override
  Future<List<Webhook>> getWebhooksForEvent(String eventType) async {
    // SQLite stores events as comma-separated string
    // Match if events contains the specific type or '*'
    final result = _db.select('''
      SELECT * FROM webhooks
      WHERE is_active = 1
        AND (events LIKE '%' || ? || '%' OR events LIKE '%*%')
      ORDER BY created_at
    ''', [eventType]);
    return result.map(_webhookFromRow).toList();
  }

  @override
  Future<void> logWebhookDelivery(WebhookDelivery delivery) async {
    _db.execute('''
      INSERT INTO webhook_deliveries
        (id, webhook_id, event_type, payload, status_code, success, error, duration_ms, delivered_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      delivery.id,
      delivery.webhookId,
      delivery.eventType,
      jsonEncode(delivery.payload),
      delivery.statusCode,
      delivery.success ? 1 : 0,
      delivery.error,
      delivery.duration.inMilliseconds,
      delivery.deliveredAt.toIso8601String(),
    ]);
  }

  @override
  Future<List<WebhookDelivery>> getWebhookDeliveries(
    String webhookId, {
    int limit = 20,
  }) async {
    final result = _db.select('''
      SELECT * FROM webhook_deliveries
      WHERE webhook_id = ?
      ORDER BY delivered_at DESC
      LIMIT ?
    ''', [webhookId, limit]);

    return result.map(_webhookDeliveryFromRow).toList();
  }

  Webhook _webhookFromRow(Row row) {
    final eventsStr = row['events'] as String;
    return Webhook(
      id: row['id'] as String,
      url: row['url'] as String,
      secret: row['secret'] as String?,
      events: eventsStr.split(',').where((e) => e.isNotEmpty).toList(),
      isActive: (row['is_active'] as int) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastTriggeredAt: row['last_triggered_at'] != null
          ? DateTime.parse(row['last_triggered_at'] as String)
          : null,
      failureCount: row['failure_count'] as int,
    );
  }

  WebhookDelivery _webhookDeliveryFromRow(Row row) {
    return WebhookDelivery(
      id: row['id'] as String,
      webhookId: row['webhook_id'] as String,
      eventType: row['event_type'] as String,
      payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
      statusCode: row['status_code'] as int,
      success: (row['success'] as int) == 1,
      error: row['error'] as String?,
      duration: Duration(milliseconds: row['duration_ms'] as int),
      deliveredAt: DateTime.parse(row['delivered_at'] as String),
    );
  }

  // ============ Backup Export Methods ============

  /// Export all packages for backup.
  Future<List<Map<String, dynamic>>> exportPackages() async {
    final result = _db.select('SELECT * FROM packages');
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Export all package versions for backup.
  Future<List<Map<String, dynamic>>> exportPackageVersions() async {
    final result = _db.select('SELECT * FROM package_versions');
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Export all users for backup.
  Future<List<Map<String, dynamic>>> exportUsers() async {
    final result = _db.select('SELECT * FROM users');
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Export all admin users for backup.
  Future<List<Map<String, dynamic>>> exportAdminUsers() async {
    final result = _db.select('SELECT * FROM admin_users');
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Export all auth tokens for backup.
  Future<List<Map<String, dynamic>>> exportAuthTokens() async {
    final result = _db.select('SELECT * FROM auth_tokens');
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Export all activity log for backup.
  Future<List<Map<String, dynamic>>> exportActivityLog() async {
    final result = _db.select('SELECT * FROM activity_log');
    return result.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  // ============ Backup Import Methods ============

  /// Import packages from backup.
  Future<void> importPackages(List<Map<String, dynamic>> packages) async {
    for (final pkg in packages) {
      _db.execute('''
        INSERT OR REPLACE INTO packages (
          name, created_at, updated_at, is_discontinued, replaced_by, is_upstream_cache, owner_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
        pkg['name'],
        pkg['created_at'],
        pkg['updated_at'],
        pkg['is_discontinued'],
        pkg['replaced_by'],
        pkg['is_upstream_cache'],
        pkg['owner_id'],
      ]);
    }
  }

  /// Import package versions from backup.
  Future<void> importPackageVersions(
      List<Map<String, dynamic>> versions) async {
    for (final v in versions) {
      _db.execute('''
        INSERT OR REPLACE INTO package_versions (
          id, package_name, version, pubspec_json, archive_key, archive_sha256, published_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
        v['id'],
        v['package_name'],
        v['version'],
        v['pubspec_json'],
        v['archive_key'],
        v['archive_sha256'],
        v['published_at'],
      ]);
    }
  }

  /// Import users from backup.
  Future<void> importUsers(List<Map<String, dynamic>> users) async {
    for (final u in users) {
      _db.execute('''
        INSERT OR REPLACE INTO users (
          id, email, password_hash, name, is_active, created_at, last_login_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
        u['id'],
        u['email'],
        u['password_hash'],
        u['name'],
        u['is_active'],
        u['created_at'],
        u['last_login_at'],
      ]);
    }
  }

  /// Import admin users from backup.
  Future<void> importAdminUsers(List<Map<String, dynamic>> adminUsers) async {
    for (final a in adminUsers) {
      _db.execute('''
        INSERT OR REPLACE INTO admin_users (
          id, username, password_hash, name, is_active, created_at, last_login_at, must_change_password
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        a['id'],
        a['username'],
        a['password_hash'],
        a['name'],
        a['is_active'],
        a['created_at'],
        a['last_login_at'],
        a['must_change_password'],
      ]);
    }
  }

  /// Import auth tokens from backup.
  Future<void> importAuthTokens(List<Map<String, dynamic>> tokens) async {
    for (final t in tokens) {
      _db.execute('''
        INSERT OR REPLACE INTO auth_tokens (
          token_hash, label, scopes, created_at, last_used_at, user_id, expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''', [
        t['token_hash'],
        t['label'],
        t['scopes'],
        t['created_at'],
        t['last_used_at'],
        t['user_id'],
        t['expires_at'],
      ]);
    }
  }

  /// Import activity log from backup.
  Future<void> importActivityLog(List<Map<String, dynamic>> activities) async {
    for (final a in activities) {
      _db.execute('''
        INSERT OR REPLACE INTO activity_log (
          id, timestamp, activity_type, actor_type, actor_id, actor_email,
          actor_username, target_type, target_id, metadata, ip_address
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        a['id'],
        a['timestamp'],
        a['activity_type'],
        a['actor_type'],
        a['actor_id'],
        a['actor_email'],
        a['actor_username'],
        a['target_type'],
        a['target_id'],
        a['metadata'],
        a['ip_address'],
      ]);
    }
  }
}

// PostgreSQL migrations
const _postgresMigrations = <String, String>{
  '001_initial': '''
    CREATE TABLE IF NOT EXISTS packages (
      name VARCHAR(255) PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      is_discontinued BOOLEAN NOT NULL DEFAULT FALSE,
      replaced_by VARCHAR(255) NULL
    );

    CREATE TABLE IF NOT EXISTS package_versions (
      id SERIAL PRIMARY KEY,
      package_name VARCHAR(255) NOT NULL REFERENCES packages(name) ON DELETE CASCADE,
      version VARCHAR(255) NOT NULL,
      pubspec_json JSONB NOT NULL,
      archive_key TEXT NOT NULL,
      archive_sha256 TEXT NOT NULL,
      published_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE(package_name, version)
    );

    CREATE INDEX IF NOT EXISTS idx_package_versions_package
      ON package_versions(package_name);

    CREATE TABLE IF NOT EXISTS auth_tokens (
      token_hash VARCHAR(64) PRIMARY KEY,
      label VARCHAR(255) NOT NULL,
      scopes TEXT[] NOT NULL DEFAULT '{}',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_used_at TIMESTAMPTZ NULL
    );

    CREATE TABLE IF NOT EXISTS upload_sessions (
      id UUID PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL,
      completed BOOLEAN NOT NULL DEFAULT FALSE
    );

    CREATE INDEX IF NOT EXISTS idx_upload_sessions_expires
      ON upload_sessions(expires_at);
  ''',
  '002_add_upstream_cache': '''
    ALTER TABLE packages ADD COLUMN is_upstream_cache BOOLEAN NOT NULL DEFAULT FALSE;
    CREATE INDEX IF NOT EXISTS idx_packages_upstream_cache ON packages(is_upstream_cache);
  ''',
  '003_add_users_and_ownership': '''
    -- User accounts table
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      email VARCHAR(255) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NULL,
      name VARCHAR(255),
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_login_at TIMESTAMPTZ NULL
    );

    -- Insert anonymous user
    INSERT INTO users (id, email, name, is_active, created_at) VALUES
      ('00000000-0000-0000-0000-000000000000', 'anonymous@localhost', 'Anonymous', TRUE, NOW())
      ON CONFLICT (id) DO NOTHING;

    -- Site configuration table
    CREATE TABLE IF NOT EXISTS site_config (
      name VARCHAR(255) PRIMARY KEY,
      value_type VARCHAR(50) NOT NULL,
      value TEXT NOT NULL,
      description TEXT
    );

    -- Insert default config values
    INSERT INTO site_config (name, value_type, value, description) VALUES
      ('allow_registration', 'boolean', 'true', 'Allow new user registration'),
      ('require_email_verification', 'boolean', 'false', 'Require email verification for new users'),
      ('allow_anonymous_publish', 'boolean', 'true', 'Allow publishing packages without authentication'),
      ('session_ttl_hours', 'number', '24', 'Web session duration in hours'),
      ('token_max_ttl_days', 'number', '0', 'Maximum token lifetime in days (0 = unlimited)')
      ON CONFLICT (name) DO NOTHING;

    -- User sessions table
    CREATE TABLE IF NOT EXISTS user_sessions (
      session_id VARCHAR(64) PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_user_sessions_user ON user_sessions(user_id);
    CREATE INDEX IF NOT EXISTS idx_user_sessions_expires ON user_sessions(expires_at);

    -- Add owner_id to packages
    ALTER TABLE packages ADD COLUMN owner_id UUID REFERENCES users(id);
    UPDATE packages SET owner_id = '00000000-0000-0000-0000-000000000000' WHERE owner_id IS NULL;

    -- Add user_id and expires_at to auth_tokens
    ALTER TABLE auth_tokens ADD COLUMN user_id UUID REFERENCES users(id);
    ALTER TABLE auth_tokens ADD COLUMN expires_at TIMESTAMPTZ NULL;
    UPDATE auth_tokens SET user_id = '00000000-0000-0000-0000-000000000000' WHERE user_id IS NULL;

    CREATE INDEX IF NOT EXISTS idx_auth_tokens_user ON auth_tokens(user_id);
    CREATE INDEX IF NOT EXISTS idx_packages_owner ON packages(owner_id);
  ''',
  '004_admin_authentication': '''
    -- Admin users table (separate from regular users)
    CREATE TABLE IF NOT EXISTS admin_users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      username VARCHAR(255) UNIQUE NOT NULL,
      password_hash VARCHAR(255) NOT NULL,
      name VARCHAR(255),
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_login_at TIMESTAMPTZ NULL
    );

    -- Add session type discriminator to user_sessions
    ALTER TABLE user_sessions ADD COLUMN IF NOT EXISTS session_type VARCHAR(50) NOT NULL DEFAULT 'user';
    CREATE INDEX IF NOT EXISTS idx_user_sessions_type ON user_sessions(session_type);
  ''',
  '005_admin_login_history': '''
    -- Admin login history table
    CREATE TABLE IF NOT EXISTS admin_login_history (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      admin_user_id UUID NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
      login_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      ip_address VARCHAR(45),
      user_agent TEXT,
      success BOOLEAN NOT NULL DEFAULT TRUE
    );

    -- Index for faster lookups by admin user
    CREATE INDEX IF NOT EXISTS idx_admin_login_history_user ON admin_login_history(admin_user_id);
    -- Index for time-based queries
    CREATE INDEX IF NOT EXISTS idx_admin_login_history_time ON admin_login_history(login_at DESC);
  ''',
  '006_admin_must_change_password': '''
    -- Add must_change_password flag for forcing password change on first login
    ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;
  ''',
  '007_package_downloads': '''
    -- Package download tracking
    CREATE TABLE IF NOT EXISTS package_downloads (
      id SERIAL PRIMARY KEY,
      package_name VARCHAR(255) NOT NULL REFERENCES packages(name) ON DELETE CASCADE,
      version VARCHAR(255) NOT NULL,
      downloaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      user_agent TEXT,
      ip_address TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_package_downloads_package ON package_downloads(package_name);
    CREATE INDEX IF NOT EXISTS idx_package_downloads_time ON package_downloads(downloaded_at DESC);
  ''',
  '008_add_default_token_scopes': '''
    -- No-op: token scopes already exist in initial migration
  ''',
  '009_activity_log': '''
    -- Activity log table
    CREATE TABLE IF NOT EXISTS activity_log (
      id SERIAL PRIMARY KEY,
      activity_type VARCHAR(50) NOT NULL,
      actor_type VARCHAR(50) NOT NULL,
      actor_id TEXT,
      target_type VARCHAR(50),
      target_id TEXT,
      description TEXT NOT NULL,
      metadata JSONB,
      ip_address TEXT,
      timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_activity_log_timestamp ON activity_log(timestamp DESC);
    CREATE INDEX IF NOT EXISTS idx_activity_log_type ON activity_log(activity_type);
    CREATE INDEX IF NOT EXISTS idx_activity_log_actor ON activity_log(actor_type, actor_id);
  ''',
  '010_webhooks': '''
    -- Webhooks table for event notifications
    CREATE TABLE IF NOT EXISTS webhooks (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      url TEXT NOT NULL,
      secret TEXT,
      events TEXT[] NOT NULL DEFAULT '{"*"}',
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      failure_count INTEGER NOT NULL DEFAULT 0,
      last_triggered_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_webhooks_active ON webhooks(is_active);

    -- Webhook delivery log
    CREATE TABLE IF NOT EXISTS webhook_deliveries (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      webhook_id UUID NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
      event_type TEXT NOT NULL,
      payload JSONB NOT NULL,
      status_code INTEGER NOT NULL,
      success BOOLEAN NOT NULL,
      error TEXT,
      duration_ms INTEGER NOT NULL,
      delivered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_time ON webhook_deliveries(delivered_at DESC);
    CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook ON webhook_deliveries(webhook_id, delivered_at DESC);
  ''',
  '011_version_retraction': '''
    -- Add retraction support to package_versions
    ALTER TABLE package_versions ADD COLUMN IF NOT EXISTS is_retracted BOOLEAN NOT NULL DEFAULT FALSE;
    ALTER TABLE package_versions ADD COLUMN IF NOT EXISTS retracted_at TIMESTAMPTZ;
    ALTER TABLE package_versions ADD COLUMN IF NOT EXISTS retraction_message TEXT;
    CREATE INDEX IF NOT EXISTS idx_package_versions_retracted ON package_versions(package_name, is_retracted);
  ''',
};

// SQLite migrations
const _sqliteMigrations = <String, String>{
  '001_initial': '''
    CREATE TABLE IF NOT EXISTS packages (
      name TEXT PRIMARY KEY,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      is_discontinued INTEGER NOT NULL DEFAULT 0,
      replaced_by TEXT NULL
    );

    CREATE TABLE IF NOT EXISTS package_versions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_name TEXT NOT NULL REFERENCES packages(name) ON DELETE CASCADE,
      version TEXT NOT NULL,
      pubspec_json TEXT NOT NULL,
      archive_key TEXT NOT NULL,
      archive_sha256 TEXT NOT NULL,
      published_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(package_name, version)
    );

    CREATE INDEX IF NOT EXISTS idx_package_versions_package
      ON package_versions(package_name);

    CREATE TABLE IF NOT EXISTS auth_tokens (
      token_hash TEXT PRIMARY KEY,
      label TEXT NOT NULL,
      scopes TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_used_at TEXT NULL
    );

    CREATE TABLE IF NOT EXISTS upload_sessions (
      id TEXT PRIMARY KEY,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL,
      completed INTEGER NOT NULL DEFAULT 0
    );

    CREATE INDEX IF NOT EXISTS idx_upload_sessions_expires
      ON upload_sessions(expires_at);
  ''',
  '002_add_upstream_cache': '''
    ALTER TABLE packages ADD COLUMN is_upstream_cache INTEGER NOT NULL DEFAULT 0;
    CREATE INDEX IF NOT EXISTS idx_packages_upstream_cache ON packages(is_upstream_cache);
  ''',
  '003_add_users_and_ownership': '''
    -- User accounts table
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NULL,
      name TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_login_at TEXT NULL
    );

    -- Insert anonymous user
    INSERT OR IGNORE INTO users (id, email, name, is_active, created_at) VALUES
      ('00000000-0000-0000-0000-000000000000', 'anonymous@localhost', 'Anonymous', 1, datetime('now'));

    -- Site configuration table
    CREATE TABLE IF NOT EXISTS site_config (
      name TEXT PRIMARY KEY,
      value_type TEXT NOT NULL,
      value TEXT NOT NULL,
      description TEXT
    );

    -- Insert default config values
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('allow_registration', 'boolean', 'true', 'Allow new user registration');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('require_email_verification', 'boolean', 'false', 'Require email verification for new users');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('allow_anonymous_publish', 'boolean', 'true', 'Allow publishing packages without authentication');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('session_ttl_hours', 'number', '24', 'Web session duration in hours');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('token_max_ttl_days', 'number', '0', 'Maximum token lifetime in days (0 = unlimited)');

    -- User sessions table
    CREATE TABLE IF NOT EXISTS user_sessions (
      session_id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      expires_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_user_sessions_user ON user_sessions(user_id);
    CREATE INDEX IF NOT EXISTS idx_user_sessions_expires ON user_sessions(expires_at);

    -- Add owner_id to packages
    ALTER TABLE packages ADD COLUMN owner_id TEXT REFERENCES users(id);

    -- Add user_id and expires_at to auth_tokens
    ALTER TABLE auth_tokens ADD COLUMN user_id TEXT REFERENCES users(id);
    ALTER TABLE auth_tokens ADD COLUMN expires_at TEXT NULL;

    CREATE INDEX IF NOT EXISTS idx_auth_tokens_user ON auth_tokens(user_id);
    CREATE INDEX IF NOT EXISTS idx_packages_owner ON packages(owner_id);
  ''',
  '004_admin_authentication': '''
    -- Admin users table (separate from regular users)
    CREATE TABLE IF NOT EXISTS admin_users (
      id TEXT PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      name TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_login_at TEXT NULL
    );

    -- Add session type discriminator to user_sessions
    ALTER TABLE user_sessions ADD COLUMN session_type TEXT NOT NULL DEFAULT 'user';
    CREATE INDEX IF NOT EXISTS idx_user_sessions_type ON user_sessions(session_type);
  ''',
  '005_admin_login_history': '''
    -- Admin login history table
    CREATE TABLE IF NOT EXISTS admin_login_history (
      id TEXT PRIMARY KEY,
      admin_user_id TEXT NOT NULL REFERENCES admin_users(id) ON DELETE CASCADE,
      login_at TEXT NOT NULL DEFAULT (datetime('now')),
      ip_address TEXT,
      user_agent TEXT,
      success INTEGER NOT NULL DEFAULT 1
    );

    -- Index for faster lookups by admin user
    CREATE INDEX IF NOT EXISTS idx_admin_login_history_user ON admin_login_history(admin_user_id);
    -- Index for time-based queries
    CREATE INDEX IF NOT EXISTS idx_admin_login_history_time ON admin_login_history(login_at DESC);
  ''',
  '006_admin_must_change_password': '''
    -- Add must_change_password flag for forcing password change on first login
    ALTER TABLE admin_users ADD COLUMN must_change_password INTEGER NOT NULL DEFAULT 0;
  ''',
  '007_package_downloads': '''
    -- Create downloads table to track package downloads
    CREATE TABLE IF NOT EXISTS package_downloads (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      package_name TEXT NOT NULL REFERENCES packages(name) ON DELETE CASCADE,
      version TEXT NOT NULL,
      downloaded_at TEXT NOT NULL DEFAULT (datetime('now')),
      user_agent TEXT,
      ip_address TEXT
    );

    -- Index for analytics queries
    CREATE INDEX IF NOT EXISTS idx_package_downloads_package ON package_downloads(package_name);
    CREATE INDEX IF NOT EXISTS idx_package_downloads_time ON package_downloads(downloaded_at);
  ''',
  '008_add_default_token_scopes': '''
    -- No-op migration for SQLite - scopes column already exists with TEXT storage
  ''',
  '009_activity_log': '''
    -- Create activity log table for tracking user and admin actions
    CREATE TABLE IF NOT EXISTS activity_log (
      id TEXT PRIMARY KEY,
      timestamp TEXT NOT NULL DEFAULT (datetime('now')),
      activity_type TEXT NOT NULL,
      actor_type TEXT NOT NULL,
      actor_id TEXT,
      actor_email TEXT,
      actor_username TEXT,
      target_type TEXT,
      target_id TEXT,
      metadata TEXT,
      ip_address TEXT
    );

    -- Index for faster queries
    CREATE INDEX IF NOT EXISTS idx_activity_log_timestamp ON activity_log(timestamp DESC);
    CREATE INDEX IF NOT EXISTS idx_activity_log_type ON activity_log(activity_type);
    CREATE INDEX IF NOT EXISTS idx_activity_log_actor ON activity_log(actor_type, actor_id);
  ''',
  '010_webhooks': '''
    -- Webhooks table for event notifications
    CREATE TABLE IF NOT EXISTS webhooks (
      id TEXT PRIMARY KEY,
      url TEXT NOT NULL,
      secret TEXT,
      events TEXT NOT NULL DEFAULT '*',
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      last_triggered_at TEXT,
      failure_count INTEGER NOT NULL DEFAULT 0
    );

    -- Webhook delivery log
    CREATE TABLE IF NOT EXISTS webhook_deliveries (
      id TEXT PRIMARY KEY,
      webhook_id TEXT NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
      event_type TEXT NOT NULL,
      payload TEXT NOT NULL,
      status_code INTEGER NOT NULL,
      success INTEGER NOT NULL,
      error TEXT,
      duration_ms INTEGER NOT NULL,
      delivered_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    -- Index for recent deliveries
    CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_time ON webhook_deliveries(delivered_at DESC);
    -- Index for webhook-specific queries
    CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook ON webhook_deliveries(webhook_id, delivered_at DESC);
  ''',
  '011_version_retraction': '''
    -- Add retraction support to package_versions
    ALTER TABLE package_versions ADD COLUMN is_retracted INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE package_versions ADD COLUMN retracted_at TEXT;
    ALTER TABLE package_versions ADD COLUMN retraction_message TEXT;

    -- Index for filtering retracted versions
    CREATE INDEX IF NOT EXISTS idx_package_versions_retracted ON package_versions(package_name, is_retracted);
  ''',
};

/// Split SQL into individual statements.
List<String> _splitStatements(String sql) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var inLineComment = false;
  var inBlockComment = false;

  for (var i = 0; i < sql.length; i++) {
    final char = sql[i];
    final nextChar = i + 1 < sql.length ? sql[i + 1] : '';

    if (!inSingleQuote && !inDoubleQuote) {
      if (inLineComment) {
        buffer.write(char);
        if (char == '\n') inLineComment = false;
        continue;
      }
      if (inBlockComment) {
        buffer.write(char);
        if (char == '*' && nextChar == '/') {
          buffer.write(nextChar);
          i++;
          inBlockComment = false;
        }
        continue;
      }
      if (char == '-' && nextChar == '-') {
        inLineComment = true;
        buffer.write(char);
        continue;
      }
      if (char == '/' && nextChar == '*') {
        inBlockComment = true;
        buffer.write(char);
        continue;
      }
    }

    if (char == "'" && !inDoubleQuote && !inLineComment && !inBlockComment) {
      inSingleQuote = !inSingleQuote;
    }
    if (char == '"' && !inSingleQuote && !inLineComment && !inBlockComment) {
      inDoubleQuote = !inDoubleQuote;
    }

    if (char == ';' &&
        !inSingleQuote &&
        !inDoubleQuote &&
        !inLineComment &&
        !inBlockComment) {
      final stmt = buffer.toString().trim();
      if (stmt.isNotEmpty) {
        statements.add(stmt);
      }
      buffer.clear();
      continue;
    }

    buffer.write(char);
  }

  final remaining = buffer.toString().trim();
  if (remaining.isNotEmpty) {
    statements.add(remaining);
  }

  return statements;
}
