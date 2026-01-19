import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:repub_model/repub_model.dart';
import 'package:uuid/uuid.dart';

/// Metadata storage backed by PostgreSQL.
class MetadataStore {
  final Connection _conn;
  static const _uuid = Uuid();

  MetadataStore(this._conn);

  // ============ Packages ============

  /// Get a package by name, returns null if not found.
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

  /// Get all versions of a package.
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
      final pubspec =
          pubspecJson is Map<String, dynamic>
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

  /// Get full package info including all versions.
  Future<PackageInfo?> getPackageInfo(String name) async {
    final package = await getPackage(name);
    if (package == null) return null;

    final versions = await getPackageVersions(name);
    return PackageInfo(package: package, versions: versions);
  }

  /// Get a specific version of a package.
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
    final pubspec =
        pubspecJson is Map<String, dynamic>
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

  /// Create or update a package and add a new version.
  Future<void> upsertPackageVersion({
    required String packageName,
    required String version,
    required Map<String, dynamic> pubspec,
    required String archiveKey,
    required String archiveSha256,
  }) async {
    await _conn.runTx((session) async {
      // Upsert package
      await session.execute(
        Sql.named('''
          INSERT INTO packages (name, created_at, updated_at)
          VALUES (@name, NOW(), NOW())
          ON CONFLICT (name) DO UPDATE SET updated_at = NOW()
        '''),
        parameters: {'name': packageName},
      );

      // Insert version
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

  /// Check if a version already exists.
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

  // ============ Auth Tokens ============

  /// Get a token by its hash.
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
    final scopesList =
        scopes is List
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

  /// Update last_used_at for a token.
  Future<void> touchToken(String tokenHash) async {
    await _conn.execute(
      Sql.named('''
        UPDATE auth_tokens SET last_used_at = NOW()
        WHERE token_hash = @hash
      '''),
      parameters: {'hash': tokenHash},
    );
  }

  /// Create a new token, returns the plaintext token.
  Future<String> createToken({
    required String label,
    required List<String> scopes,
  }) async {
    // Generate a secure random token
    final token = _uuid.v4() + _uuid.v4(); // 64 chars
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

  /// List all tokens (without exposing hashes in a way that matters).
  Future<List<Map<String, dynamic>>> listTokens() async {
    final result = await _conn.execute('''
      SELECT label, scopes, created_at, last_used_at
      FROM auth_tokens ORDER BY created_at DESC
    ''');

    return result.map((row) {
      final scopes = row[1];
      return {
        'label': row[0] as String,
        'scopes':
            scopes is List
                ? scopes.cast<String>()
                : (scopes as List<dynamic>).cast<String>(),
        'created_at': (row[2] as DateTime).toIso8601String(),
        'last_used_at': (row[3] as DateTime?)?.toIso8601String(),
      };
    }).toList();
  }

  /// Delete a token by label.
  Future<bool> deleteToken(String label) async {
    final result = await _conn.execute(
      Sql.named('DELETE FROM auth_tokens WHERE label = @label'),
      parameters: {'label': label},
    );
    return result.affectedRows > 0;
  }

  // ============ Upload Sessions ============

  /// Create an upload session.
  Future<UploadSession> createUploadSession({
    Duration ttl = const Duration(hours: 1),
  }) async {
    final id = _uuid.v4();
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

  /// Get an upload session by ID.
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

  /// Mark an upload session as completed.
  Future<void> completeUploadSession(String id) async {
    await _conn.execute(
      Sql.named('UPDATE upload_sessions SET completed = TRUE WHERE id = @id'),
      parameters: {'id': id},
    );
  }

  /// Clean up expired sessions.
  Future<int> cleanupExpiredSessions() async {
    final result = await _conn.execute(
      'DELETE FROM upload_sessions WHERE expires_at < NOW()',
    );
    return result.affectedRows;
  }
}
