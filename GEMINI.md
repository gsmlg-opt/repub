# Repub: Self-Hosted Dart Package Registry

Repub is a modular, self-hosted Dart package registry implementing the [Hosted Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md). It is managed as a Melos monorepo.

## Project Structure

- **`packages/repub_model/`**: Shared domain models, configuration logic, and core utilities. Zero internal dependencies.
- **`packages/repub_auth/`**: Token-based and session-based authentication and authorization logic.
- **`packages/repub_storage/`**: Abstraction layer for metadata (SQLite/PostgreSQL) and blob storage (Local File/S3).
- **`packages/repub_migrate/`**: SQL migration system for database schema management.
- **`packages/repub_server/`**: Main HTTP server (Shelf) providing the registry API, public web UI, and admin API.
- **`packages/repub_cli/`**: Administrative CLI for user management, migrations, and storage activation.
- **`packages/repub_web/`**: Public-facing web UI for package browsing (built with Jaspr).
- **`packages/repub_admin/`**: Admin dashboard for registry management (built with Flutter Web).

## Critical Constraints & Architecture

- **Auth**: Two systems:
    1. **Bearer Tokens**: Scoped access for `dart pub` operations (managed via Web UI).
    2. **Admin Sessions**: Cookie-based access for the Admin UI (managed via CLI).
- **Security**: 
    - No SSL in-app; use a reverse proxy for TLS termination.
    - Passwords MUST be encrypted using RSA-OAEP (SHA-256) before sending to the server.
    - Webhooks include SSRF protection and HMAC-SHA256 signatures.
- **Development**: Use the unified dev server (`melos run dev`) which proxies API and hot-reloading UI servers.
- **Production Build Issue**: Jaspr has known `dart2js` compilation issues. Use the Docker image or `melos run dev` (DDC) for deployment.

## Common Development Commands

### Setup & Development
```bash
# Bootstrap the workspace
melos bootstrap

# Start unified development server (API + Web UI + Admin UI on port 4920)
melos run dev

# Run API server only (SQLite + local storage)
melos run server
```

### Quality & Testing
```bash
# Run tests in all packages
melos run test

# Run static analysis
melos run analyze

# Format code
melos run format
```

### Administration
```bash
# Run database migrations
melos run migrate

# Create an admin user (CLI only)
dart run -C packages/repub_cli repub_cli admin create <username> <password> [name]

# Activate pending storage configuration
dart run -C packages/repub_cli repub_cli storage activate
```

## Configuration (Environment Variables)

- `REPUB_LISTEN_ADDR`: Listen address (default: `0.0.0.0:4920`).
- `REPUB_BASE_URL`: Public URL of the registry.
- `REPUB_DATABASE_URL`: Connection string (`sqlite:./path` or `postgres://...`).
- `REPUB_STORAGE_PATH`: Local storage directory (if using local storage).
- `REPUB_S3_*`: S3 credentials and bucket (if using S3).
- `REPUB_ENCRYPTION_KEY`: Hex-encoded 256-bit key for encrypting S3 credentials in the DB.

## Documentation Reference
- **API Spec**: See [`openapi.yaml`](./openapi.yaml).
- **Detailed Guidance**: See [`CLAUDE.md`](./CLAUDE.md) for architecture deep-dives and specific handler logic.
