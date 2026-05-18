/// SQL migrations in order.
/// Each migration has an 'up' script.
const postgresMigrations = <String, String>{
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
      id TEXT PRIMARY KEY,
      timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      activity_type VARCHAR(50) NOT NULL,
      actor_type VARCHAR(50) NOT NULL,
      actor_id TEXT,
      actor_email TEXT,
      actor_username TEXT,
      target_type VARCHAR(50),
      target_id TEXT,
      metadata JSONB,
      ip_address TEXT
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
  '012_fix_activity_log': '''
    -- Fix activity_log table schema (add missing columns and fix id type)
    -- Drop and remake table with correct schema
    DROP TABLE IF EXISTS activity_log CASCADE;
    CREATE TABLE IF NOT EXISTS activity_log (
      id TEXT PRIMARY KEY,
      timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      activity_type VARCHAR(50) NOT NULL,
      actor_type VARCHAR(50) NOT NULL,
      actor_id TEXT,
      actor_email TEXT,
      actor_username TEXT,
      target_type VARCHAR(50),
      target_id TEXT,
      metadata JSONB,
      ip_address TEXT
    );
    CREATE INDEX IF NOT EXISTS idx_activity_log_timestamp ON activity_log(timestamp DESC);
    CREATE INDEX IF NOT EXISTS idx_activity_log_type ON activity_log(activity_type);
    CREATE INDEX IF NOT EXISTS idx_activity_log_actor ON activity_log(actor_type, actor_id);
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
  '014_storage_config': '''
    -- Storage configuration (active)
    INSERT INTO site_config (name, value_type, value, description) VALUES
      ('storage_config_initialized', 'boolean', 'false', 'Whether storage config has been initialized'),
      ('storage_type', 'string', 'local', 'Storage backend: local or s3'),
      ('storage_local_path', 'string', './data/storage', 'Local filesystem storage path'),
      ('storage_cache_path', 'string', './data/cache', 'Cache path for upstream packages'),
      ('storage_s3_endpoint', 'string', '', 'S3/MinIO endpoint URL'),
      ('storage_s3_region', 'string', 'us-east-1', 'S3 region'),
      ('storage_s3_access_key', 'string', '', 'S3 access key (encrypted)'),
      ('storage_s3_secret_key', 'string', '', 'S3 secret key (encrypted)'),
      ('storage_s3_bucket', 'string', '', 'S3 bucket name'),
      ('storage_pending_config_initialized', 'boolean', 'false', 'Whether pending storage config exists'),
      ('storage_pending_type', 'string', 'local', 'Pending storage backend: local or s3'),
      ('storage_pending_local_path', 'string', './data/storage', 'Pending local filesystem storage path'),
      ('storage_pending_cache_path', 'string', './data/cache', 'Pending cache path for upstream packages'),
      ('storage_pending_s3_endpoint', 'string', '', 'Pending S3/MinIO endpoint URL'),
      ('storage_pending_s3_region', 'string', 'us-east-1', 'Pending S3 region'),
      ('storage_pending_s3_access_key', 'string', '', 'Pending S3 access key (encrypted)'),
      ('storage_pending_s3_secret_key', 'string', '', 'Pending S3 secret key (encrypted)'),
      ('storage_pending_s3_bucket', 'string', '', 'Pending S3 bucket name')
    ON CONFLICT (name) DO NOTHING;
  ''',
  '015_fix_pending_storage_key': '''
    -- Fix naming: storage_pending_initialized -> storage_pending_config_initialized
    UPDATE site_config SET name = 'storage_pending_config_initialized'
      WHERE name = 'storage_pending_initialized';
    -- Insert correct name if it doesn't exist (fresh installs that already ran fixed 014)
    INSERT INTO site_config (name, value_type, value, description)
      VALUES ('storage_pending_config_initialized', 'boolean', 'false', 'Whether pending storage config exists')
      ON CONFLICT (name) DO NOTHING;
  ''',
};

// SQLite migrations

/// Get all migrations that haven't been applied yet.
List<MapEntry<String, String>> getPendingMigrations(
    Set<String> applied, Map<String, String> allMigrations) {
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
