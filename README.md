# Repub

A self-hosted Dart/Flutter package registry implementing the [Hosted Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md).

## Features

- **Publish packages**: Full support for `dart pub publish`
- **Install packages**: Works with `dart pub get` using hosted URLs
- **Bearer token auth**: Secure publish with scoped tokens
- **S3 storage**: Package archives stored in S3-compatible storage (MinIO)
- **PostgreSQL metadata**: Package metadata stored in PostgreSQL
- **Melos monorepo**: Modular architecture with clear package boundaries

## Non-goals

- pub.dev analyzer/scoring
- Mirroring/proxying pub.dev
- Web UI
- User accounts / OAuth

## Project Structure

This is a Melos-managed monorepo (Melos >= 7.0):

```
repub/
├── melos.yaml              # Melos workspace configuration
├── pubspec.yaml            # Root workspace pubspec
├── packages/
│   ├── repub_model/        # Shared domain models
│   ├── repub_auth/         # Token + scope validation
│   ├── repub_storage/      # PostgreSQL + S3 storage
│   ├── repub_migrate/      # SQL migrations
│   ├── repub_server/       # HTTP server (main API)
│   └── repub_cli/          # Admin CLI
├── docker-compose.yml
├── Dockerfile
└── scripts/
    └── smoke_test.sh
```

## Quickstart

### 1. Install Melos

```bash
dart pub global activate melos
```

### 2. Bootstrap the workspace

```bash
melos bootstrap
```

### 3. Start the services

```bash
docker compose up -d
```

This starts:
- PostgreSQL (port 5432)
- MinIO (ports 9000, 9001 for console)
- Repub server (port 8080)

### 4. Create an auth token

```bash
docker compose exec repub /app/bin/repub_cli token create my-token publish:all
```

Save the token output - you'll need it for publishing.

### 5. Add the token to dart pub

```bash
dart pub token add http://localhost:8080
```

Paste the token when prompted.

### 6. Publish a package

In your package directory, add `publish_to` to pubspec.yaml:

```yaml
name: my_package
version: 1.0.0
publish_to: http://localhost:8080
```

Then publish:

```bash
dart pub publish
```

### 7. Use the package

In a consuming project:

```yaml
dependencies:
  my_package:
    hosted:
      url: http://localhost:8080
    version: ^1.0.0
```

Then:

```bash
dart pub get
```

## Melos Scripts

```bash
# Bootstrap all packages
melos bootstrap

# Analyze all packages
melos run analyze

# Run tests in all packages
melos run test

# Format all packages
melos run format

# Check formatting
melos run format:check
```

## Configuration

All configuration is via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `REPUB_LISTEN_ADDR` | `0.0.0.0:8080` | Listen address |
| `REPUB_BASE_URL` | `http://localhost:8080` | Public URL of the registry |
| `REPUB_DATABASE_URL` | `postgres://repub:repub@localhost:5432/repub` | PostgreSQL connection URL |
| `REPUB_S3_ENDPOINT` | `http://localhost:9000` | S3/MinIO endpoint |
| `REPUB_S3_REGION` | `us-east-1` | S3 region |
| `REPUB_S3_ACCESS_KEY` | `minioadmin` | S3 access key |
| `REPUB_S3_SECRET_KEY` | `minioadmin` | S3 secret key |
| `REPUB_S3_BUCKET` | `repub` | S3 bucket name |
| `REPUB_REQUIRE_DOWNLOAD_AUTH` | `false` | Require auth for downloads |
| `REPUB_SIGNED_URL_TTL_SECONDS` | `3600` | TTL for signed URLs |

## API Endpoints

### Package Info

```
GET /api/packages/<name>
```

Returns package metadata with all versions.

### Publish Flow

```
GET /api/packages/versions/new
```

Requires `Authorization: Bearer <token>`. Returns upload URL.

```
POST /api/packages/versions/upload/<session>
```

Upload the package tarball.

```
GET /api/packages/versions/finalize/<session>
```

Validate and complete the publish.

### Download

```
GET /packages/<name>/versions/<version>.tar.gz
```

Download a package archive.

### Health Check

```
GET /health
```

Returns `{"status": "ok"}`.

## Token Scopes

| Scope | Description |
|-------|-------------|
| `admin` | Full access |
| `publish:all` | Publish any package |
| `publish:pkg:<name>` | Publish specific package |
| `read:all` | Read/download (if `REQUIRE_DOWNLOAD_AUTH=true`) |

## CLI Commands

```bash
# Start server (via repub_cli)
dart run -C packages/repub_cli repub_cli serve

# Run migrations
dart run -C packages/repub_cli repub_cli migrate

# Token management
dart run -C packages/repub_cli repub_cli token create <label> [scopes...]
dart run -C packages/repub_cli repub_cli token list
dart run -C packages/repub_cli repub_cli token delete <label>

# Or directly with repub_server
dart run -C packages/repub_server repub_server
```

## Running the Smoke Test

```bash
# Start services
docker compose up -d

# Run smoke test
./scripts/smoke_test.sh
```

## Development

```bash
# Install melos
dart pub global activate melos

# Bootstrap workspace
melos bootstrap

# Run locally (requires postgres and minio)
export REPUB_DATABASE_URL="postgres://repub:repub@localhost:5432/repub"
export REPUB_S3_ENDPOINT="http://localhost:9000"
dart run -C packages/repub_server repub_server
```

## Package Dependencies

```
repub_model (no internal deps)
    ↑
repub_auth (depends on: repub_model)
    ↑
repub_migrate (no internal deps, uses postgres)
    ↑
repub_storage (depends on: repub_model)
    ↑
repub_server (depends on: repub_model, repub_auth, repub_storage, repub_migrate)
    ↑
repub_cli (depends on: repub_model, repub_storage, repub_migrate, repub_server)
```

## License

MIT
