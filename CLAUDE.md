# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Critical Constraints

- Client auth tokens are not mandatory — this is a self-hosted project used only by the package owner.
- Do not add SSL support; the project runs behind a reverse proxy.
- Do not change the default listen address in development mode.
- The CLI (`repub_cli`) manages admin users, database operations, and storage configuration. Regular user registration, token management, and all other user operations are handled via the web UI. Do not add CLI commands for token creation, user registration, or other non-admin operations.
- **PRODUCTION BUILD ISSUE**: The Jaspr web UI has known issues with dart2js compilation that produce broken JavaScript. Use `melos run dev` (DDC compiler) for both development AND production. Do not attempt to "fix" dart2js builds — this is an upstream Jaspr issue.
- At login, encrypt the user's password with the server's RSA public key (RSA-OAEP with SHA-256) before transmission. Never send plaintext passwords.

## Build & Development Commands

```bash
# Bootstrap workspace (run first)
melos bootstrap

# Development - unified server on port 4920 with hot reload
melos run dev

# Run API server only (SQLite + local storage)
melos run server

# Build production binaries/UIs
melos run build            # Compile native server binary
melos run build:web        # Build Jaspr web UI
melos run build:admin      # Build Flutter admin UI

# Run dev servers individually
melos run dev:web          # Jaspr on port 4921
melos run dev:admin        # Flutter on port 4922

# Quality checks
melos run analyze          # Static analysis with fatal-infos
melos run format           # Format all Dart files
melos run format:check     # Check formatting without changes
melos run test             # Run tests in all packages

# Run a single test file
dart test packages/repub_server/test/webhook_test.dart

# Run a single test by name
dart test packages/repub_server/test/webhook_test.dart --name "delivers webhook"

# Database
melos run migrate

# Database reset (development only)
dart run -C packages/repub_cli repub_cli db:reset --force

# Admin user management
dart run -C packages/repub_cli repub_cli admin create <username> <password> [name]
dart run -C packages/repub_cli repub_cli admin list
```

## Architecture

Melos 7.x monorepo implementing the [Hosted Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md). Dart SDK >=3.6.0.

### Package Dependency Graph

```
repub_model (foundation — shared domain models, zero deps)
    ↑
repub_auth ← repub_storage (SQLite/PostgreSQL + local/S3)
    ↑            ↑
    └────────────┴──→ repub_server (Shelf HTTP) ← repub_cli
                            ↑
                    repub_migrate (SQL migrations)
                            ↑
                    repub_web (Jaspr)    repub_admin (Flutter)
```

### Key Entry Points

- `packages/repub_server/bin/repub_server.dart` — Production server entry
- `packages/repub_server/bin/repub_dev_server.dart` — Dev proxy server (API + web + admin on port 4920)
- `packages/repub_server/lib/src/handlers.dart` — All API route definitions and handler class
- `packages/repub_server/lib/src/server.dart` — Server startup, middleware pipeline assembly
- `packages/repub_storage/lib/src/metadata.dart` — `MetadataStore` abstract class with `SqliteMetadataStore`/`PostgresMetadataStore` implementations
- `packages/repub_storage/lib/src/blobs.dart` — `BlobStore` abstract class with `FileBlobStore`/`S3BlobStore` implementations
- `packages/repub_migrate/lib/src/migrations.dart` — Ordered SQL migration definitions
- `packages/repub_model/lib/src/config.dart` — `Config.fromEnv()` reads all environment variables
- `packages/repub_admin/lib/services/admin_api_client.dart` — Admin UI HTTP client for all admin API calls

### Server Middleware Pipeline

Requests flow through this Shelf pipeline (defined in `server.dart`):

```
Request → logRequests → CORS → Version headers → IP whitelist (optional) → Rate limiting → Router
```

- CORS: Configurable via `REPUB_CORS_ALLOWED_ORIGINS`
- IP whitelist: Only applies to `/admin` paths when `REPUB_ADMIN_IP_WHITELIST` is set
- Rate limiting: Composite key (IP + user agent + path prefix), excludes `/health` and `/metrics`

### Storage Abstraction

Database and blob storage are selected at runtime based on environment variables:

- `REPUB_DATABASE_URL=sqlite:./path` → `SqliteMetadataStore` (default)
- `REPUB_DATABASE_URL=postgres://...` → `PostgresMetadataStore`
- `REPUB_STORAGE_PATH=./path` → `FileBlobStore` (default)
- `REPUB_S3_*` vars → `S3BlobStore`

Two separate `BlobStore` instances exist: one for hosted packages, one for cached upstream packages (different key prefixes).

### Storage Configuration (Database-Backed)

Storage config (local vs S3, credentials) is persisted to the database. On first startup, env vars are read and saved; subsequent startups read from DB. Changing storage is a **two-stage process**:

1. **Edit pending config** in admin UI (saves `storage_pending_*` fields in `site_config` table)
2. **Activate via CLI** with server stopped: `dart run repub_cli storage activate` (copies `storage_pending_*` → `storage_*` fields)

Key files:
- `repub_model/lib/src/config.dart` — `StorageConfig` model, `ConfigEncryption` (AES-256-GCM)
- `repub_storage/lib/src/metadata.dart` — `getStorageConfig()`, `initializeStorageConfig()`, `getPendingStorageConfig()`, `savePendingStorageConfig()`, `activatePendingStorageConfig()`
- `repub_server/lib/src/handlers.dart` — `GET /admin/api/storage/config`, `PUT /admin/api/storage/pending`
- `repub_cli/lib/src/storage_commands.dart` — `storage show`, `storage activate`
- `repub_admin/lib/models/storage_config_info.dart` — Admin UI storage config model

S3 credentials are encrypted in the DB with AES-256-GCM using `REPUB_ENCRYPTION_KEY`. The `REPUB_FORCE_ENV_STORAGE_CONFIG=true` flag overrides DB config for disaster recovery.

### Two Authentication Systems

1. **Bearer Tokens** (API access for `dart pub`): Stored as SHA-256 hashes in `auth_tokens` table. Scoped: `admin`, `publish:all`, `publish:pkg:<name>`, `read:all`. Managed via web UI at `/account/tokens`.

2. **Admin Sessions** (admin panel): Cookie-based (`admin_session`), 8-hour TTL, `SameSite=Strict`, `Path=/admin`. Admin users managed exclusively via CLI. Login history tracked in `admin_login_history` table.

Password encryption: Server generates an ephemeral RSA-2048 key pair on startup. Public key served at `/api/public-key`. Clients encrypt passwords with RSA-OAEP/SHA-256 before sending.

### Migration System

Migrations are defined as ordered SQL strings in `packages/repub_migrate/lib/src/migrations.dart`. Each migration is keyed like `'001_initial'`, `'002_upstream_cache'`, etc. Migrations use PostgreSQL syntax; SQLite compatibility is handled by the store implementations. Applied migrations are tracked in the `schema_migrations` table.

### Dev Server Proxy Architecture

`scripts/dev.sh` starts three processes:
1. `repub_dev_server.dart` on port 4920 — handles API routes directly, proxies everything else
2. Jaspr webdev on port 4921 — hot-reloading web UI
3. Flutter dev server on port 4922 — hot-reloading admin UI

The dev server routes: `/api/*`, `/admin/api/*`, `/packages/*`, `/health` → direct handling; `/admin/*` → proxy to 4922; everything else → proxy to 4921.

### Admin UI (Flutter) — BLoC Pattern

State management uses `flutter_bloc`. Each feature has a dedicated BLoC directory:

```
lib/blocs/{feature}/
├── {feature}_bloc.dart    # Event handlers, API calls
├── {feature}_event.dart   # Load, Refresh, Delete, etc.
└── {feature}_state.dart   # Initial, Loading, Loaded, Error
```

BLoCs: `dashboard`, `local_packages`, `cached_packages`, `users`, `admin_users`, `webhooks`, `config`. All use `AdminApiClient` for HTTP calls. Tests use `bloc_test` and `mocktail`.

### Testing

Tests use the `test` package. Server integration tests create in-memory SQLite databases via `SqliteMetadataStore`. Admin UI tests use `bloc_test` for BLoC testing and `mocktail` for mocking `AdminApiClient`.

Key test files:
- `repub_server/test/test_helper.dart` — Shared test constants (e.g., `testEncryptionKey`)
- `repub_server/test/auth_integration_test.dart` — Auth flow tests
- `repub_server/test/webhook_test.dart` — Webhook delivery, SSRF protection
- `repub_admin/test/blocs/` — BLoC unit tests
- `repub_admin/test/widgets/` — Widget tests

### Webhook System

Defined in `packages/repub_server/lib/src/webhook_service.dart`. Events: `package.published`, `package.deleted`, `version.deleted`, `package.discontinued`, `package.reactivated`, `user.registered`, `cache.cleared`, `*` (wildcard). HMAC-SHA256 signatures via `X-Webhook-Signature` header. SSRF protection blocks private IPs, localhost, and cloud metadata endpoints at both creation and delivery time. Auto-disables after 5 consecutive failures.

## Environment Variables

Core: `REPUB_LISTEN_ADDR` (default `0.0.0.0:4920`), `REPUB_BASE_URL`, `REPUB_REQUIRE_DOWNLOAD_AUTH`

Database: `REPUB_DATABASE_URL` (`sqlite:./path` or `postgres://...`), `REPUB_DATABASE_RETRY_ATTEMPTS`, `REPUB_DATABASE_RETRY_DELAY_SECONDS`

Storage: `REPUB_STORAGE_PATH` (local) or `REPUB_S3_ENDPOINT`, `REPUB_S3_ACCESS_KEY`, `REPUB_S3_SECRET_KEY`, `REPUB_S3_BUCKET`, `REPUB_S3_REGION` (env vars only used on first startup, then persisted to DB)

Encryption: `REPUB_ENCRYPTION_KEY` (hex 256-bit key for DB credential encryption, auto-generated if not set), `REPUB_FORCE_ENV_STORAGE_CONFIG` (override DB config with env vars)

Security: `REPUB_CORS_ALLOWED_ORIGINS`, `REPUB_ADMIN_IP_WHITELIST`, `REPUB_RATE_LIMIT_REQUESTS` (default 100), `REPUB_RATE_LIMIT_WINDOW_SECONDS` (default 60)

Logging: `REPUB_LOG_LEVEL` (debug/info/warn/error), `REPUB_LOG_JSON`

## Docker

```bash
# Standalone (SQLite + local storage, zero external deps)
docker run -p 4920:4920 -v repub_data:/data ghcr.io/gsmlg-dev/repub:latest

# With PostgreSQL + MinIO
docker compose up -d
```

Multi-stage Dockerfile: build stage uses Flutter SDK + Melos, compiles native executables and static assets. Runtime stage is debian-slim with only ca-certificates and libsqlite3.
