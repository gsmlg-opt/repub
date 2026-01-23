/// SQL migrations in order.
/// Each migration has an 'up' script.
const migrations = <String, String>{
  '001_initial': '''
    -- Schema version tracking
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version VARCHAR(255) PRIMARY KEY,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- Packages table
    CREATE TABLE IF NOT EXISTS packages (
      name VARCHAR(255) PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      is_discontinued BOOLEAN NOT NULL DEFAULT FALSE,
      replaced_by VARCHAR(255) NULL
    );

    -- Package versions table
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

    -- Index for faster version lookups
    CREATE INDEX IF NOT EXISTS idx_package_versions_package
      ON package_versions(package_name);

    -- Auth tokens table
    CREATE TABLE IF NOT EXISTS auth_tokens (
      token_hash VARCHAR(64) PRIMARY KEY,
      label VARCHAR(255) NOT NULL,
      scopes TEXT[] NOT NULL DEFAULT '{}',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_used_at TIMESTAMPTZ NULL
    );

    -- Upload sessions (for publish flow)
    CREATE TABLE IF NOT EXISTS upload_sessions (
      id UUID PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL,
      completed BOOLEAN NOT NULL DEFAULT FALSE
    );

    -- Index for session cleanup
    CREATE INDEX IF NOT EXISTS idx_upload_sessions_expires
      ON upload_sessions(expires_at);
  ''',
  '002_upstream_cache': '''
    -- Add upstream cache flag to packages
    -- This marks packages that were cached from upstream (e.g., pub.dev)
    ALTER TABLE packages ADD COLUMN IF NOT EXISTS is_upstream_cache BOOLEAN NOT NULL DEFAULT FALSE;

    -- Index for filtering local vs cached packages
    CREATE INDEX IF NOT EXISTS idx_packages_upstream_cache
      ON packages(is_upstream_cache);
  ''',
};

/// Get all migrations that haven't been applied yet.
List<MapEntry<String, String>> getPendingMigrations(Set<String> applied) {
  return migrations.entries.where((e) => !applied.contains(e.key)).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
}
