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
  '003_admin_authentication': '''
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
  '004_admin_login_history': '''
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
  '005_admin_must_change_password': '''
    -- Add must_change_password flag for forcing password change on first login
    ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;
  ''',
  '006_admin_must_change_password_fix': '''
    -- Duplicate of 005 for databases that have 006_admin_must_change_password applied
    -- This is a no-op migration to maintain consistency
    SELECT 1;
  ''',
  '007_package_downloads': '''
    -- Package downloads tracking table
    CREATE TABLE IF NOT EXISTS package_downloads (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      package_name VARCHAR(255) NOT NULL,
      version VARCHAR(255) NOT NULL,
      downloaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      ip_address VARCHAR(45),
      user_agent TEXT
    );

    -- Index for time-based queries (most common query pattern)
    CREATE INDEX IF NOT EXISTS idx_package_downloads_time ON package_downloads(downloaded_at DESC);

    -- Index for package-specific queries
    CREATE INDEX IF NOT EXISTS idx_package_downloads_package ON package_downloads(package_name, downloaded_at DESC);
  ''',
  '008_add_default_token_scopes': '''
    -- Add default admin scope to existing tokens for backwards compatibility
    -- Existing deployments had no scope enforcement, so existing tokens effectively had full access
    -- This migration ensures they continue to work by granting admin scope
    UPDATE auth_tokens
    SET scopes = ARRAY['admin']::TEXT[]
    WHERE scopes = '{}' OR scopes IS NULL;
  ''',
};

/// Get all migrations that haven't been applied yet.
List<MapEntry<String, String>> getPendingMigrations(Set<String> applied) {
  return migrations.entries.where((e) => !applied.contains(e.key)).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
}
