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
      final conn = await _connectPostgres(config.databaseUrl);
      return PostgresMetadataStore(conn);
    }
  }

  static Future<Connection> _connectPostgres(String databaseUrl) async {
    final uri = Uri.parse(databaseUrl);
    final userInfo = uri.userInfo.split(':');

    final endpoint = Endpoint(
      host: uri.host,
      port: uri.hasPort ? uri.port : 5432,
      database: uri.pathSegments.isNotEmpty ? uri.pathSegments.first : 'repub',
      username: userInfo.isNotEmpty ? userInfo[0] : 'repub',
      password: userInfo.length > 1 ? userInfo[1] : 'repub',
    );

    for (var i = 0; i < 30; i++) {
      try {
        return await Connection.open(
          endpoint,
          settings: ConnectionSettings(sslMode: SslMode.disable),
        );
      } catch (e) {
        if (i == 29) rethrow;
        print('Waiting for database... (${i + 1}/30)');
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    throw StateError('Could not connect to database');
  }

  /// Run database migrations.
  Future<int> runMigrations();

  /// Close the database connection.
  Future<void> close();

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
  Future<void> upsertPackageVersion({
    required String packageName,
    required String version,
    required Map<String, dynamic> pubspec,
    required String archiveKey,
    required String archiveSha256,
  });

  /// Check if a version already exists.
  Future<bool> versionExists(String packageName, String version);

  // ============ Auth Tokens ============

  /// Get a token by its hash.
  Future<AuthToken?> getTokenByHash(String tokenHash);

  /// Update last_used_at for a token.
  Future<void> touchToken(String tokenHash);

  /// Create a new token, returns the plaintext token.
  Future<String> createToken({
    required String label,
    required List<String> scopes,
  });

  /// List all tokens.
  Future<List<Map<String, dynamic>>> listTokens();

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
      print('Applying migration: ${migration.key}');
      await _conn.runTx((session) async {
        final statements = _splitStatements(migration.value);
        for (final statement in statements) {
          if (statement.trim().isNotEmpty) {
            await session.execute(statement);
          }
        }
        await session.execute(
          Sql.named('INSERT INTO schema_migrations (version) VALUES (@version)'),
          parameters: {'version': migration.key},
        );
      });
      count++;
    }
    return count;
  }

  @override
  Future<void> close() async {
    await _conn.close();
  }

  @override
  Future<Package?> getPackage(String name) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT name, created_at, updated_at, is_discontinued, replaced_by
        FROM packages WHERE name = @name
      '''),
      parameters: {'name': name},
    );

    if (result.isEmpty) return null;

    final row = result.first;
    return Package(
      name: row[0] as String,
      createdAt: row[1] as DateTime,
      updatedAt: row[2] as DateTime,
      isDiscontinued: row[3] as bool,
      replacedBy: row[4] as String?,
    );
  }

  @override
  Future<List<PackageVersion>> getPackageVersions(String packageName) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT package_name, version, pubspec_json, archive_key, archive_sha256, published_at
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
        SELECT package_name, version, pubspec_json, archive_key, archive_sha256, published_at
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
    );
  }

  @override
  Future<void> upsertPackageVersion({
    required String packageName,
    required String version,
    required Map<String, dynamic> pubspec,
    required String archiveKey,
    required String archiveSha256,
  }) async {
    await _conn.runTx((session) async {
      await session.execute(
        Sql.named('''
          INSERT INTO packages (name, created_at, updated_at)
          VALUES (@name, NOW(), NOW())
          ON CONFLICT (name) DO UPDATE SET updated_at = NOW()
        '''),
        parameters: {'name': packageName},
      );

      await session.execute(
        Sql.named('''
          INSERT INTO package_versions
            (package_name, version, pubspec_json, archive_key, archive_sha256, published_at)
          VALUES (@name, @version, @pubspec, @archive_key, @sha256, NOW())
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
  Future<AuthToken?> getTokenByHash(String tokenHash) async {
    final result = await _conn.execute(
      Sql.named('''
        SELECT token_hash, label, scopes, created_at, last_used_at
        FROM auth_tokens WHERE token_hash = @hash
      '''),
      parameters: {'hash': tokenHash},
    );

    if (result.isEmpty) return null;

    final row = result.first;
    final scopes = row[2];
    final scopesList = scopes is List
        ? scopes.cast<String>()
        : (scopes as List<dynamic>).cast<String>();

    return AuthToken(
      tokenHash: row[0] as String,
      label: row[1] as String,
      scopes: scopesList,
      createdAt: row[3] as DateTime,
      lastUsedAt: row[4] as DateTime?,
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
    required String label,
    required List<String> scopes,
  }) async {
    final token = MetadataStore._uuid.v4() + MetadataStore._uuid.v4();
    final tokenHash = sha256.convert(utf8.encode(token)).toString();

    await _conn.execute(
      Sql.named('''
        INSERT INTO auth_tokens (token_hash, label, scopes)
        VALUES (@hash, @label, @scopes)
      '''),
      parameters: {'hash': tokenHash, 'label': label, 'scopes': scopes},
    );

    return token;
  }

  @override
  Future<List<Map<String, dynamic>>> listTokens() async {
    final result = await _conn.execute('''
      SELECT label, scopes, created_at, last_used_at
      FROM auth_tokens ORDER BY created_at DESC
    ''');

    return result.map((row) {
      final scopes = row[1];
      return {
        'label': row[0] as String,
        'scopes': scopes is List
            ? scopes.cast<String>()
            : (scopes as List<dynamic>).cast<String>(),
        'created_at': (row[2] as DateTime).toIso8601String(),
        'last_used_at': (row[3] as DateTime?)?.toIso8601String(),
      };
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
      print('Applying migration: ${migration.key}');
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
  Future<void> close() async {
    _db.dispose();
  }

  @override
  Future<Package?> getPackage(String name) async {
    final result = _db.select('''
      SELECT name, created_at, updated_at, is_discontinued, replaced_by
      FROM packages WHERE name = ?
    ''', [name]);

    if (result.isEmpty) return null;

    final row = result.first;
    return Package(
      name: row['name'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      isDiscontinued: (row['is_discontinued'] as int) == 1,
      replacedBy: row['replaced_by'] as String?,
    );
  }

  @override
  Future<List<PackageVersion>> getPackageVersions(String packageName) async {
    final result = _db.select('''
      SELECT package_name, version, pubspec_json, archive_key, archive_sha256, published_at
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
      SELECT package_name, version, pubspec_json, archive_key, archive_sha256, published_at
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
    );
  }

  @override
  Future<void> upsertPackageVersion({
    required String packageName,
    required String version,
    required Map<String, dynamic> pubspec,
    required String archiveKey,
    required String archiveSha256,
  }) async {
    final now = DateTime.now().toIso8601String();

    _db.execute('BEGIN TRANSACTION');
    try {
      _db.execute('''
        INSERT INTO packages (name, created_at, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT (name) DO UPDATE SET updated_at = ?
      ''', [packageName, now, now, now]);

      _db.execute('''
        INSERT INTO package_versions
          (package_name, version, pubspec_json, archive_key, archive_sha256, published_at)
        VALUES (?, ?, ?, ?, ?, ?)
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
  Future<AuthToken?> getTokenByHash(String tokenHash) async {
    final result = _db.select('''
      SELECT token_hash, label, scopes, created_at, last_used_at
      FROM auth_tokens WHERE token_hash = ?
    ''', [tokenHash]);

    if (result.isEmpty) return null;

    final row = result.first;
    final scopesJson = row['scopes'] as String;
    final scopes = (jsonDecode(scopesJson) as List).cast<String>();

    return AuthToken(
      tokenHash: row['token_hash'] as String,
      label: row['label'] as String,
      scopes: scopes,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastUsedAt: row['last_used_at'] != null
          ? DateTime.parse(row['last_used_at'] as String)
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
    required String label,
    required List<String> scopes,
  }) async {
    final token = MetadataStore._uuid.v4() + MetadataStore._uuid.v4();
    final tokenHash = sha256.convert(utf8.encode(token)).toString();
    final now = DateTime.now().toIso8601String();

    _db.execute('''
      INSERT INTO auth_tokens (token_hash, label, scopes, created_at)
      VALUES (?, ?, ?, ?)
    ''', [tokenHash, label, jsonEncode(scopes), now]);

    return token;
  }

  @override
  Future<List<Map<String, dynamic>>> listTokens() async {
    final result = _db.select('''
      SELECT label, scopes, created_at, last_used_at
      FROM auth_tokens ORDER BY created_at DESC
    ''');

    return result.map((row) {
      final scopesJson = row['scopes'] as String;
      return {
        'label': row['label'] as String,
        'scopes': (jsonDecode(scopesJson) as List).cast<String>(),
        'created_at': row['created_at'] as String,
        'last_used_at': row['last_used_at'] as String?,
      };
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
