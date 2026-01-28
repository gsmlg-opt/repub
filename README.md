# Repub

A self-hosted Dart/Flutter package registry implementing the [Hosted Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md).

## Features

- **Publish packages**: Full support for `dart pub publish`
- **Install packages**: Works with `dart pub get` using hosted URLs
- **Bearer token auth**: Secure publish with scoped tokens
- **Public web UI**: Package browsing and documentation (built with Jaspr)
- **Admin UI**: Web-based admin dashboard for package and user management (built with Flutter)
- **Admin users**: Separate admin authentication with login history tracking
- **Flexible storage**: Package archives stored locally or in S3-compatible storage (MinIO, AWS S3)
- **Flexible database**: SQLite (default) or PostgreSQL for metadata
- **Zero external dependencies**: Docker image uses SQLite + local storage by default
- **Melos monorepo**: Modular architecture with clear package boundaries
- **Automated releases**: CI/CD with automatic Docker image building

## Non-goals

- pub.dev analyzer/scoring
- Mirroring/proxying pub.dev
- User accounts / OAuth (self-hosted for package owners only)

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
│   ├── repub_cli/          # Admin CLI
│   ├── repub_web/          # Public web UI (Jaspr)
│   └── repub_admin/        # Admin web UI (Flutter)
├── docker-compose.yml
├── Dockerfile
└── scripts/
    ├── smoke_test.sh
    └── dev.sh              # Development environment script
```

## Quickstart

### Option A: Docker Standalone (Zero Dependencies)

The Docker image uses SQLite + local file storage by default, requiring no external services:

```bash
# Run with persistent volume
docker run -d \
  -p 4920:4920 \
  -v repub_data:/data \
  ghcr.io/gsmlg-dev/repub:latest

# Create an admin user (for accessing /admin UI)
docker exec <container_id> /app/bin/repub_cli admin create admin password123 "Admin User"

# Note: User tokens are managed via the web UI
# 1. Register/login at http://localhost:4920/login
# 2. Navigate to /account/tokens to create publish tokens
```

Data is stored in `/data`:
- SQLite database: `/data/metadata/repub.db`
- Package archives: `/data/packages/`
- Cache: `/data/cache/`

The Docker image includes:
- Repub server (compiled native executable)
- Public web UI (Jaspr, served at `/`)
- Admin UI (Flutter, served at `/admin`)

### Option B: Docker Compose (PostgreSQL + MinIO)

For production with external database and S3-compatible storage:

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
- Repub server (port 4920)

### 4. Create a user account and token

Register a user account to create publish tokens:

```bash
# Visit http://localhost:4920/register to create an account
# Then login at http://localhost:4920/login
# Navigate to /account/tokens to create publish tokens
```

Optionally, create an admin user to access the admin UI at `/admin`:

```bash
docker compose exec repub /app/bin/repub_cli admin create admin password123 "Admin User"
```

### 5. Add the token to dart pub

```bash
dart pub token add http://localhost:4920
```

Paste the token when prompted.

### 6. Publish a package

In your package directory, add `publish_to` to pubspec.yaml:

```yaml
name: my_package
version: 1.0.0
publish_to: http://localhost:4920
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
      url: http://localhost:4920
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

# Development - unified server on port 4920 (API + web UI + admin UI with hot reload)
melos run dev

# Run individual dev servers
melos run dev:web          # Jaspr web UI on port 4921
melos run dev:admin        # Flutter admin UI on port 4922
melos run server           # API server only

# Build
melos run build            # Build production binaries
melos run build:web        # Build Jaspr web UI for production
melos run build:admin      # Build Flutter admin UI for production

# Quality checks
melos run analyze          # Analyze all packages with fatal-infos
melos run test             # Run tests in all packages
melos run format           # Format all Dart files
melos run format:check     # Check formatting without changes

# Database
melos run migrate          # Run database migrations
```

## Configuration

All configuration is via environment variables:

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `REPUB_LISTEN_ADDR` | `0.0.0.0:4920` | Listen address |
| `REPUB_BASE_URL` | `http://localhost:4920` | Public URL of the registry |
| `REPUB_REQUIRE_DOWNLOAD_AUTH` | `false` | Require auth for downloads |

### Database Options

Choose between SQLite (default, zero-config) or PostgreSQL:

#### Option 1: SQLite (Default)

| Variable | Default | Description |
|----------|---------|-------------|
| `REPUB_DATABASE_URL` | `sqlite:./data/repub.db` | SQLite database file path |

Example:
```bash
export REPUB_DATABASE_URL=sqlite:/var/lib/repub/repub.db
```

#### Option 2: PostgreSQL

| Variable | Default | Description |
|----------|---------|-------------|
| `REPUB_DATABASE_URL` | *(none)* | PostgreSQL connection URL |

Example:
```bash
export REPUB_DATABASE_URL=postgres://repub:repub@localhost:5432/repub
```

### Storage Options

You can use either local file storage or S3-compatible storage. Set **one** of the following:

#### Option 1: Local File Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `REPUB_STORAGE_PATH` | *(none)* | Local directory for package archives |

Example:
```bash
export REPUB_STORAGE_PATH=/var/lib/repub/packages
```

#### Option 2: S3-Compatible Storage (MinIO, AWS S3, etc.)

| Variable | Default | Description |
|----------|---------|-------------|
| `REPUB_S3_ENDPOINT` | *(none)* | S3/MinIO endpoint URL |
| `REPUB_S3_REGION` | `us-east-1` | S3 region |
| `REPUB_S3_ACCESS_KEY` | *(none)* | S3 access key |
| `REPUB_S3_SECRET_KEY` | *(none)* | S3 secret key |
| `REPUB_S3_BUCKET` | *(none)* | S3 bucket name |
| `REPUB_SIGNED_URL_TTL_SECONDS` | `3600` | TTL for signed download URLs |

Example:
```bash
export REPUB_S3_ENDPOINT=http://localhost:9000
export REPUB_S3_ACCESS_KEY=minioadmin
export REPUB_S3_SECRET_KEY=minioadmin
export REPUB_S3_BUCKET=repub
```

### Email Notifications

Email notifications are configured via the Site Configuration in the admin panel (`/admin`). Navigate to Site Configuration to set up SMTP:

| Setting | Default | Description |
|---------|---------|-------------|
| `smtp_host` | *(empty)* | SMTP server hostname |
| `smtp_port` | `587` | SMTP server port |
| `smtp_username` | *(empty)* | SMTP authentication username |
| `smtp_password` | *(empty)* | SMTP authentication password |
| `smtp_from_address` | *(empty)* | Sender email address |
| `smtp_from_name` | `Repub Package Registry` | Sender name |
| `smtp_ssl` | `false` | Use SSL/TLS for SMTP connection |
| `email_notifications_enabled` | `false` | Enable email notifications |
| `email_on_package_published` | `true` | Send email when a package is published |
| `email_on_user_registered` | `true` | Send welcome email when a user registers |

When enabled, the following emails are sent:
- **Welcome email**: Sent to new users upon registration
- **Package published**: Sent to the publisher when a package version is published

## API Documentation

**Full API specification**: See [`openapi.yaml`](./openapi.yaml) for the complete OpenAPI 3.0 specification.

View the spec with:
- [Swagger UI](https://editor.swagger.io/) - paste the openapi.yaml content
- [Redocly](https://redocly.github.io/redoc/) - interactive documentation
- Any OpenAPI-compatible tool

### Quick Reference

#### Package Info

```
GET /api/packages/<name>
```

Returns package metadata with all versions.

#### Publish Flow

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

Validate and complete the publish. Requires appropriate scope (admin, publish:all, or publish:pkg:<name>).

#### Download

```
GET /packages/<name>/versions/<version>.tar.gz
```

Download a package archive.

### Health Check

```
GET /health
```

Returns `{"status": "ok"}`.

### RSS/Atom Feeds

Subscribe to package updates via RSS or Atom feeds:

**Global feeds** (all recent package updates):
```
GET /feed.rss       # RSS 2.0 feed
GET /feed.atom      # Atom 1.0 feed
```

**Per-package feeds** (updates for specific package):
```
GET /packages/{name}/feed.rss    # RSS 2.0 feed
GET /packages/{name}/feed.atom   # Atom 1.0 feed
```

Feeds include the 20 most recent package version releases. Response is cached for 5 minutes.

### Admin API Endpoints

All admin endpoints require admin session authentication (cookie-based).

```
GET /admin/api/stats
```

Returns dashboard statistics (total packages, local/cached packages, versions).

```
GET /admin/api/analytics/packages-created?days=30
```

Returns packages created per day for the last N days. Response format: `{"2026-01-27": 5, "2026-01-26": 3, ...}`

```
GET /admin/api/analytics/downloads?hours=24
```

Returns package downloads per hour for the last N hours. Response format: `{"2026-01-27 15:00:00": 12, "2026-01-27 14:00:00": 8, ...}`

```
GET /admin/api/packages/local
GET /admin/api/packages/cached
DELETE /admin/api/packages/<name>
DELETE /admin/api/packages/<name>/versions/<version>
POST /admin/api/packages/<name>/discontinue
DELETE /admin/api/cache
```

Package and cache management endpoints.

### Webhooks

Subscribe to registry events via webhooks. Webhooks are managed via the admin API.

**Available event types:**
- `package.published` - When a package version is published
- `package.deleted` - When a package is deleted
- `version.deleted` - When a specific version is deleted
- `package.discontinued` - When a package is marked discontinued
- `package.reactivated` - When a discontinued package is reactivated
- `user.registered` - When a new user registers
- `cache.cleared` - When cache is cleared
- `*` - Wildcard, subscribes to all events

**Webhook payload format:**
```json
{
  "event": "package.published",
  "timestamp": "2026-01-27T15:30:00Z",
  "data": {
    "package": "my_package",
    "version": "1.0.0",
    "publisher_email": "user@example.com"
  }
}
```

**Security:** Webhooks support HMAC-SHA256 signature verification. If a secret is configured, the `X-Webhook-Signature` header contains `sha256=<signature>` computed from the request body.

**Admin API endpoints:**
```
GET    /admin/api/webhooks              # List all webhooks
POST   /admin/api/webhooks              # Create webhook
GET    /admin/api/webhooks/<id>         # Get webhook details
PUT    /admin/api/webhooks/<id>         # Update webhook
DELETE /admin/api/webhooks/<id>         # Delete webhook
GET    /admin/api/webhooks/<id>/deliveries  # View delivery history
POST   /admin/api/webhooks/<id>/test    # Send test payload
```

Webhooks are automatically disabled after 5 consecutive delivery failures to prevent repeated failures.

## Token Scopes

Repub uses scope-based authorization to control what operations tokens can perform. Tokens are managed through the web UI at `/account/tokens`.

| Scope | Description | Example Use Case |
|-------|-------------|------------------|
| `admin` | Full access including admin panel operations | Internal admin automation |
| `publish:all` | Publish any package to the registry | CI/CD pipeline for multiple packages |
| `publish:pkg:<name>` | Publish only the specific named package | Package-specific CI/CD token |
| `read:all` | Read/download packages (only needed if `REQUIRE_DOWNLOAD_AUTH=true`) | Private package access |

### Scope Examples

**Publishing multiple packages (CI/CD):**
```
Scopes: ["publish:all"]
Can: Publish any package
Cannot: Delete packages, access admin panel
```

**Publishing a specific package:**
```
Scopes: ["publish:pkg:my_package"]
Can: Publish only my_package
Cannot: Publish other packages, delete anything
```

**Admin operations:**
```
Scopes: ["admin"]
Can: Everything (publish, delete, admin operations)
```

**No scopes (authentication only):**
```
Scopes: []
Can: Authenticate (verify user identity)
Cannot: Any write operations
```

### Authorization Flow

1. **Token Creation**: Users create tokens via `/account/tokens` and select which scopes to grant
2. **API Request**: Client sends `Authorization: Bearer <token>` header
3. **Token Validation**: Server verifies token hash and checks expiration
4. **Scope Check**: Server validates token has required scope for the operation
5. **Operation**: If authorized, operation proceeds; otherwise returns 403 Forbidden

### Security Best Practices

#### Token Management
- **Principle of Least Privilege**: Create tokens with minimal required scopes
- **Package-Specific Tokens**: Use `publish:pkg:<name>` for single-package CI/CD
- **Token Rotation**: Regularly rotate tokens, especially for CI/CD
- **Expiration**: Set expiration dates on tokens when possible (admin can enforce max TTL)
- **Revocation**: Revoke tokens immediately if compromised (via web UI)

#### Password Requirements
User passwords must meet the following complexity requirements:
- Minimum 8 characters
- At least one uppercase letter (A-Z)
- At least one lowercase letter (a-z)
- At least one number (0-9)

#### Deployment Security
- **Reverse Proxy**: Always deploy behind a reverse proxy (nginx, traefik, caddy) for TLS termination
- **CORS Configuration**: Set `REPUB_CORS_ALLOWED_ORIGINS` to your frontend domain(s) in production
- **IP Whitelisting**: Use `REPUB_ADMIN_IP_WHITELIST` to restrict admin panel access to trusted IPs
- **Rate Limiting**: Configure `REPUB_RATE_LIMIT_REQUESTS` and `REPUB_RATE_LIMIT_WINDOW_SECONDS` to prevent abuse

#### Environment Variables for Security

| Variable | Default | Description |
|----------|---------|-------------|
| `REPUB_CORS_ALLOWED_ORIGINS` | (baseUrl only) | Comma-separated allowed CORS origins, or `*` for wildcard |
| `REPUB_ADMIN_IP_WHITELIST` | (disabled) | Comma-separated IPs/CIDRs allowed to access admin panel |
| `REPUB_RATE_LIMIT_REQUESTS` | 100 | Max requests per window |
| `REPUB_RATE_LIMIT_WINDOW_SECONDS` | 60 | Rate limit window in seconds |
| `REPUB_DATABASE_RETRY_ATTEMPTS` | 30 | Number of database connection retry attempts |
| `REPUB_DATABASE_RETRY_DELAY_SECONDS` | 1 | Delay between database connection retries |
| `REPUB_LOG_LEVEL` | info | Logging level (debug, info, warn, error) |
| `REPUB_LOG_JSON` | false | Enable JSON format logging for log aggregators |

**CORS Examples:**
```bash
# Allow specific frontend domains
REPUB_CORS_ALLOWED_ORIGINS="https://packages.mycompany.com,https://admin.mycompany.com"

# Development mode (allows all origins - NOT for production)
REPUB_CORS_ALLOWED_ORIGINS="*"
```

**IP Whitelist Examples:**
```bash
# Allow specific IPs
REPUB_ADMIN_IP_WHITELIST="192.168.1.100,10.0.0.50"

# Allow CIDR range
REPUB_ADMIN_IP_WHITELIST="192.168.1.0/24,10.0.0.0/8"

# Allow localhost only
REPUB_ADMIN_IP_WHITELIST="localhost"
```

#### Webhook Security
- **SSRF Protection**: Webhook URLs cannot target private/internal IP ranges:
  - localhost, 127.x.x.x (loopback)
  - 10.x.x.x, 192.168.x.x, 172.16-31.x.x (private networks)
  - 169.254.x.x (link-local, including AWS metadata service)
  - IPv6 private ranges
- **Signature Verification**: Configure a webhook secret for HMAC-SHA256 payload verification
- **HTTPS**: Always use HTTPS URLs for webhooks in production

## CLI Commands

```bash
# Start server (via repub_cli)
dart run -C packages/repub_cli repub_cli serve

# Run migrations
dart run -C packages/repub_cli repub_cli migrate

# Database reset (drop all tables, recreate schema, seed data)
# WARNING: This deletes ALL data!
dart run -C packages/repub_cli repub_cli db:reset              # Interactive (prompts for confirmation)
dart run -C packages/repub_cli repub_cli db:reset --force      # Non-interactive (no prompts)
dart run -C packages/repub_cli repub_cli db:reset --seed       # Force seed data without prompting
dart run -C packages/repub_cli repub_cli db:reset --force -s   # Non-interactive with seed data

# Admin user management (CLI-only for security)
dart run -C packages/repub_cli repub_cli admin create <username> <password> [name]
dart run -C packages/repub_cli repub_cli admin list
dart run -C packages/repub_cli repub_cli admin reset-password <username> <new-password>
dart run -C packages/repub_cli repub_cli admin activate <username>
dart run -C packages/repub_cli repub_cli admin deactivate <username>
dart run -C packages/repub_cli repub_cli admin delete <username>

# Note: User token management is done via the web UI
# Navigate to /account/tokens after logging in

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

## Known Issues

### Production Web UI Build (Jaspr + dart2js)

**Issue**: The production web UI build using dart2js produces JavaScript compilation errors that prevent form submissions and event handlers from working correctly.

**Symptoms**:
- Registration form doesn't submit
- Login form doesn't work
- JavaScript console shows errors like "s.gag is not a function" or "A.k(...).gj7 is not a function"
- Forms appear to load but clicking submit does nothing

**Root Cause**: The combination of Jaspr framework and dart2js compilation (even with optimization level -O2 and minification disabled) produces malformed JavaScript.

**Current Workaround**: Use the development server which uses the DDC (dartdevc) compiler instead of dart2js:

```bash
# Development server works perfectly for all operations
melos run dev

# Access at http://localhost:4920
# All features work: registration, login, token creation, package publishing
```

**Status**: This is a known upstream issue with Jaspr's build process. The development server is fully functional and suitable for both development and production use. For production deployments, consider:

1. **Option A (Recommended)**: Deploy using `melos run dev` behind a reverse proxy (nginx/caddy/traefik)
2. **Option B**: Use the Docker image which includes pre-built static assets that work correctly
3. **Option C**: Wait for upstream Jaspr fixes to dart2js compatibility

**Tracked at**: [Issue report to be filed with Jaspr team]

---

## Development

```bash
# Install melos
dart pub global activate melos

# Bootstrap workspace
melos bootstrap

# Start unified dev server on port 4920 (API + Web UI with hot reload)
# This is the recommended way for development AND production
melos run dev

# Or run API server only with SQLite + local storage
export REPUB_DATABASE_URL="sqlite:./data/repub.db"
export REPUB_STORAGE_PATH="./data/packages"
dart run -C packages/repub_server repub_server

# Or run with PostgreSQL + local storage
export REPUB_DATABASE_URL="postgres://repub:repub@localhost:5432/repub"
export REPUB_STORAGE_PATH="./data/packages"
dart run -C packages/repub_server repub_server

# Or run with PostgreSQL + S3/MinIO
export REPUB_DATABASE_URL="postgres://repub:repub@localhost:5432/repub"
export REPUB_S3_ENDPOINT="http://localhost:9000"
export REPUB_S3_ACCESS_KEY="minioadmin"
export REPUB_S3_SECRET_KEY="minioadmin"
export REPUB_S3_BUCKET="repub"
dart run -C packages/repub_server repub_server
```

### Development Server

The `melos run dev` command starts a unified development server on **port 4920** that includes:
- **API server** - All API endpoints at `/api/*`, `/admin/api/*`, `/packages/*`, `/health`
- **Public Web UI** - Package browsing, search, and documentation (Jaspr with hot reload)
- **Admin UI** - Admin dashboard and package management at `/admin` (Flutter with hot reload)
- **Single URL** - Access everything at `http://localhost:4920`

The dev server internally proxies:
- Web UI requests to Jaspr webdev (running on 4921)
- Admin UI requests to Flutter dev server (running on 4922)

This provides instant hot reload when you modify any frontend code.

**Accessing the UIs in development:**
- Public UI: `http://localhost:4920`
- Admin UI: `http://localhost:4920/admin` (requires admin user - see Admin UI section)
- API: `http://localhost:4920/api/*`

You'll need to create an admin user first to access the admin UI:
```bash
# Create admin user for development
export REPUB_DATABASE_URL="sqlite:./data/repub.db"
dart run -C packages/repub_cli repub_cli admin create admin password123 "Admin User"
```

## Admin UI

The admin dashboard is a Flutter web application accessible at `/admin`. It uses BLoC pattern for state management and provides:

### Features

- **Dashboard**: Overview stats (total packages, local/cached packages, versions)
- **Analytics Charts**:
  - Bar chart: Packages created per day (last 30 days)
  - Line chart: Package downloads per hour (last 24 hours)
- **Package Management**: View, delete, and discontinue packages
- **User Management**: Create and manage regular users
- **Admin Users**: View admin users and their login history
- **Site Configuration**: Configure registry settings
- **Cache Management**: Clear upstream package cache
- **Download Tracking**: Automatic logging of all package downloads with IP address and user agent

### Admin User Management

Admin users are managed **exclusively via CLI** for security:

```bash
# Create an admin user
dart run repub_cli admin create myusername mypassword "My Name"

# List all admin users
dart run repub_cli admin list

# Reset password
dart run repub_cli admin reset-password myusername newpassword

# Deactivate/activate admin user
dart run repub_cli admin deactivate myusername
dart run repub_cli admin activate myusername

# Delete admin user
dart run repub_cli admin delete myusername
```

### Admin Login History

All admin login attempts are tracked with:
- Timestamp
- IP address (from `X-Forwarded-For` or `X-Real-IP` headers)
- User agent
- Success/failure status

View login history in the Admin UI at `/admin/admin-users` → select user → view detailed login history.

Failed login attempts are highlighted in red for easy identification of potential security issues.

### Admin Authentication

- Admin users have separate authentication from regular users
- Admin sessions use a separate `admin_session` cookie with stricter security:
  - Path restricted to `/admin`
  - `SameSite=Strict`
  - 8-hour session TTL (shorter than regular users)
- All `/admin/api/*` endpoints require admin authentication
- Admin users cannot be created through the web UI

## CI/CD

This project uses GitHub Actions for continuous integration and automated releases:

### Continuous Integration
- **Dependency check**: Validates all dependencies resolve correctly
- **Analyze**: Runs `dart analyze` with fatal-infos on all packages
- **Format check**: Ensures code is properly formatted
- **Tests**: Runs all package tests

All checks use Flutter SDK to support both Dart and Flutter packages.

### Automated Releases

Releases are automated via GitHub Actions workflow:

1. **Trigger**: Run "Release" workflow from GitHub Actions tab
2. **Version bump**: Choose patch, minor, or major version bump
3. **Release notes**: Automatically categorized by commit type (feat, fix, docs, chore)
4. **Git tag**: Creates and pushes version tag (e.g., `v1.6.4`)
5. **GitHub release**: Creates release with categorized changelog
6. **Docker image**: Automatically builds and pushes multi-arch image to `ghcr.io/gsmlg-dev/repub`

Docker images are tagged with:
- `vX.Y.Z` (e.g., `v1.6.4`)
- `X.Y.Z` (e.g., `1.6.4`)
- `latest`

All images are built for `linux/amd64` and `linux/arm64` platforms.

## Package Dependencies

```
repub_model (no internal deps)
    ↑
repub_auth (depends on: repub_model)
    ↑
repub_storage (depends on: repub_model; includes SQLite + PostgreSQL + S3)
    ↑
repub_server (depends on: repub_model, repub_auth, repub_storage)
    ↑
    ├── repub_cli (depends on: repub_model, repub_storage, repub_server)
    ├── repub_web (depends on: repub_model; Jaspr web UI)
    └── repub_admin (depends on: repub_model; Flutter admin UI)
```

## License

MIT
