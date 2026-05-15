/// SQL migrations in order.
/// Each migration has an 'up' script.
const postgresMigrations = <String, String>{
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
  '009_activity_log': '''
    -- Activity log table for tracking user and admin actions
    CREATE TABLE IF NOT EXISTS activity_log (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      activity_type VARCHAR(50) NOT NULL, -- 'package_published', 'user_registered', 'admin_login', 'package_deleted', etc.
      actor_type VARCHAR(20) NOT NULL, -- 'user', 'admin', 'system'
      actor_id UUID NULL, -- user_id or admin_user_id
      actor_email VARCHAR(255) NULL, -- email for display
      actor_username VARCHAR(255) NULL, -- username for admins
      target_type VARCHAR(50) NULL, -- 'package', 'user', 'config', etc.
      target_id VARCHAR(255) NULL, -- package name, user id, etc.
      metadata JSONB NULL, -- additional context (version, ip, etc.)
      ip_address VARCHAR(45) NULL
    );

    -- Index for recent activity queries
    CREATE INDEX IF NOT EXISTS idx_activity_log_timestamp ON activity_log(timestamp DESC);
    -- Index for filtering by type
    CREATE INDEX IF NOT EXISTS idx_activity_log_type ON activity_log(activity_type);
    -- Index for actor-based queries
    CREATE INDEX IF NOT EXISTS idx_activity_log_actor ON activity_log(actor_type, actor_id);
  ''',
  '010_webhooks': '''
    -- Webhooks table for event notifications
    CREATE TABLE IF NOT EXISTS webhooks (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      url TEXT NOT NULL,
      secret VARCHAR(255) NULL, -- HMAC secret for signing payloads
      events TEXT[] NOT NULL DEFAULT ARRAY['*']::TEXT[], -- event types to trigger on, '*' = all
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      last_triggered_at TIMESTAMPTZ NULL,
      failure_count INTEGER NOT NULL DEFAULT 0
    );

    -- Webhook delivery log
    CREATE TABLE IF NOT EXISTS webhook_deliveries (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      webhook_id UUID NOT NULL REFERENCES webhooks(id) ON DELETE CASCADE,
      event_type VARCHAR(50) NOT NULL,
      payload JSONB NOT NULL,
      status_code INTEGER NOT NULL,
      success BOOLEAN NOT NULL,
      error TEXT NULL,
      duration_ms INTEGER NOT NULL,
      delivered_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    -- Index for recent deliveries
    CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_time ON webhook_deliveries(delivered_at DESC);
    -- Index for webhook-specific queries
    CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_webhook ON webhook_deliveries(webhook_id, delivered_at DESC);
  ''',
  '011_version_retraction': '''
    -- Add version retraction support to package_versions
    -- Retracted versions are still available for download but marked as problematic
    -- Useful for security vulnerabilities or critical bugs
    ALTER TABLE package_versions ADD COLUMN IF NOT EXISTS is_retracted BOOLEAN NOT NULL DEFAULT FALSE;
    ALTER TABLE package_versions ADD COLUMN IF NOT EXISTS retracted_at TIMESTAMPTZ NULL;
    ALTER TABLE package_versions ADD COLUMN IF NOT EXISTS retraction_message TEXT NULL;

    -- Index for filtering retracted versions
    CREATE INDEX IF NOT EXISTS idx_package_versions_retracted ON package_versions(is_retracted);
  ''',
  '012_performance_indexes': '''
    -- Performance optimization indexes based on query pattern analysis
    -- These indexes improve the performance of frequently-used queries

    -- CRITICAL: Optimize package search with LIKE patterns
    -- Used by searchPackages() which filters on is_upstream_cache and searches name
    CREATE INDEX IF NOT EXISTS idx_packages_search
      ON packages(is_upstream_cache, name);

    -- CRITICAL: Optimize package list query with filter+order
    -- Used by listPackages() which filters by is_upstream_cache and orders by updated_at
    CREATE INDEX IF NOT EXISTS idx_packages_list
      ON packages(is_upstream_cache, updated_at DESC);

    -- HIGH: Optimize user login by email lookup
    -- Used by getUserByEmail() during authentication
    CREATE INDEX IF NOT EXISTS idx_users_email
      ON users(email);

    -- HIGH: Optimize admin authentication by username
    -- Used by getAdminUserByUsername() during admin login
    CREATE INDEX IF NOT EXISTS idx_admin_users_username
      ON admin_users(username);

    -- MEDIUM: Optimize token expiration validation
    -- Used for token cleanup and validation queries
    CREATE INDEX IF NOT EXISTS idx_auth_tokens_expires
      ON auth_tokens(expires_at);

    -- MEDIUM: Optimize activity log filtering with type+time
    -- Used by getRecentActivity() when filtering by activity type
    CREATE INDEX IF NOT EXISTS idx_activity_log_type_timestamp
      ON activity_log(activity_type, timestamp DESC);

    -- MEDIUM: Optimize download statistics aggregations
    -- Used by getPackageDownloadStats() for time-based download analytics
    CREATE INDEX IF NOT EXISTS idx_package_downloads_package_time
      ON package_downloads(package_name, downloaded_at DESC);
  ''',
  '013_fix_admin_sessions': '''
    -- Fix admin session foreign key constraint
    -- The user_sessions table stores both regular user and admin sessions
    -- (differentiated by session_type column), but the foreign key constraint
    -- only allows user IDs from the users table, not admin_users table.
    -- We need to drop this constraint to allow admin user IDs.

    -- Drop the foreign key constraint on user_sessions.user_id
    ALTER TABLE user_sessions DROP CONSTRAINT IF EXISTS user_sessions_user_id_fkey;

    -- Note: We don't add a new constraint because sessions can reference either
    -- users(id) or admin_users(id) depending on session_type.
    -- The application logic enforces referential integrity.
  ''',
};

/// Get all migrations that haven't been applied yet.
List<MapEntry<String, String>> getPendingMigrations(Set<String> applied, Map<String, String> allMigrations) {
  return allMigrations.entries.where((e) => !applied.contains(e.key)).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
}

const sqliteMigrations = <String, String>{
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
  '012_fix_activity_log': '''
    -- No-op: SQLite schema already has correct columns from migration 009
  ''',
  '013_fix_admin_sessions': '''
    -- No-op: SQLite doesn't enforce foreign keys by default (PRAGMA foreign_keys not enabled)
    -- Admin sessions work without modification
  ''',
  '014_storage_config': '''
    -- Storage configuration (active)
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_config_initialized', 'boolean', 'false', 'Whether storage config has been initialized');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_type', 'string', 'local', 'Storage backend: local or s3');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_local_path', 'string', './data/storage', 'Local filesystem storage path');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_cache_path', 'string', './data/cache', 'Cache path for upstream packages');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_s3_endpoint', 'string', '', 'S3/MinIO endpoint URL');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_s3_region', 'string', 'us-east-1', 'S3 region');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_s3_access_key', 'string', '', 'S3 access key (encrypted)');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_s3_secret_key', 'string', '', 'S3 secret key (encrypted)');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_s3_bucket', 'string', '', 'S3 bucket name');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_config_initialized', 'boolean', 'false', 'Whether pending storage config exists');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_type', 'string', 'local', 'Pending storage backend: local or s3');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_local_path', 'string', './data/storage', 'Pending local filesystem storage path');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_cache_path', 'string', './data/cache', 'Pending cache path for upstream packages');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_s3_endpoint', 'string', '', 'Pending S3/MinIO endpoint URL');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_s3_region', 'string', 'us-east-1', 'Pending S3 region');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_s3_access_key', 'string', '', 'Pending S3 access key (encrypted)');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_s3_secret_key', 'string', '', 'Pending S3 secret key (encrypted)');
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_s3_bucket', 'string', '', 'Pending S3 bucket name');
  ''',
  '015_fix_pending_storage_key': '''
    -- Fix naming: storage_pending_initialized -> storage_pending_config_initialized
    UPDATE site_config SET name = 'storage_pending_config_initialized'
      WHERE name = 'storage_pending_initialized';
    INSERT OR IGNORE INTO site_config (name, value_type, value, description) VALUES
      ('storage_pending_config_initialized', 'boolean', 'false', 'Whether pending storage config exists');
  ''',
};

