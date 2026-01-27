# Product Requirements Document: Repub

**Version:** 1.0
**Last Updated:** 2026-01-27
**Status:** Active Development

## Executive Summary

Repub is a self-hosted Dart/Flutter package registry that implements the [Hosted Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md). It enables organizations and individual developers to host private Dart/Flutter packages without relying on external services, with zero mandatory external dependencies.

## Product Vision

Enable Dart/Flutter developers to own and control their package distribution infrastructure with a lightweight, secure, and production-ready private package registry that works out of the box.

## Target Users

### Primary Personas

1. **Enterprise Development Teams**
   - Need: Private package hosting for proprietary code
   - Pain Points: Security concerns, compliance requirements, cost of external services
   - Goals: Self-hosted solution with full control over data and infrastructure

2. **Solo Developers / Small Teams**
   - Need: Simple private package registry for personal/small projects
   - Pain Points: Complexity of existing solutions, infrastructure overhead
   - Goals: Zero-config deployment, minimal maintenance

3. **Organizations with Air-Gapped Environments**
   - Need: Package registry without internet connectivity
   - Pain Points: Cannot use cloud-based registries
   - Goals: Fully offline-capable solution

## Core Principles

1. **Self-Hosted First**: Designed for users to run on their own infrastructure
2. **Zero External Dependencies**: Works with SQLite + local storage out of the box
3. **Specification Compliant**: Fully implements Pub Repository Spec v2
4. **Production Ready**: Docker images, automated releases, version tracking
5. **Developer Friendly**: Simple setup, clear documentation, intuitive admin UI

## Feature Requirements

### Must Have (v1.0)

#### 1. Package Management
- **Publish Packages** (`dart pub publish`)
  - Upload package tarballs
  - Validate package metadata (pubspec.yaml)
  - Generate and store package metadata
  - Support for all package versions

- **Install Packages** (`dart pub get`)
  - Download package archives
  - Serve package metadata in Pub Spec v2 format
  - Optional download authentication

- **Package Listing**
  - List all packages with pagination
  - View package details (all versions, README, changelog)
  - Search packages by name/description
  - Display package statistics

#### 2. Authentication & Authorization

- **Bearer Token Authentication**
  - Create tokens with scoped permissions
  - Token-based publish authentication
  - Optional download authentication

- **Token Scopes**
  - `admin`: Full access including admin panel
  - `publish:all`: Publish any package
  - `publish:pkg:<name>`: Publish specific package only
  - `read:all`: Read/download (when download auth required)

- **Admin User System**
  - Separate admin authentication (distinct from API tokens)
  - Session-based authentication (8-hour TTL)
  - Login history tracking (IP, user agent, success/failure)
  - CLI-only user management (no web-based admin user creation for security)

- **Regular User System**
  - User registration and login via web UI
  - Session-based authentication (24-hour TTL)
  - User token management
  - Profile management

#### 3. Storage Flexibility

- **Database Options**
  - SQLite (default, zero-config)
  - PostgreSQL (production deployments)

- **Blob Storage Options**
  - Local filesystem (default)
  - S3-compatible storage (MinIO, AWS S3)

#### 4. Web Interfaces

- **Public Web UI** (Jaspr framework)
  - Browse packages
  - Search packages
  - View package documentation
  - User registration/login
  - Token management
  - Account settings

- **Admin UI** (Flutter web)
  - Dashboard with statistics
  - Analytics charts:
    - Bar chart: Packages created per day (last 30 days)
    - Line chart: Package downloads per hour (last 24 hours)
  - Package management (delete, discontinue)
  - User management
  - Admin user viewing (with login history)
  - Cache management
  - Site configuration
  - Download tracking (automatic logging with IP and user agent)

#### 5. Developer Experience

- **CLI Administration**
  - Server management (`serve`, `migrate`)
  - Admin user management (`admin create`, `admin list`, `admin reset-password`, `admin activate`, `admin deactivate`, `admin delete`)
  - Note: User tokens are managed via web UI at `/account/tokens` (not CLI)

- **Development Mode**
  - Unified dev server (single port for API + both UIs)
  - Hot reload for both web UIs
  - Auto-migration on startup

#### 6. Deployment & Operations

- **Docker Support**
  - Multi-arch images (linux/amd64, linux/arm64)
  - Version and git hash tracking
  - Zero-config SQLite + local storage by default
  - Environment variable configuration

- **Docker Compose**
  - Full stack with PostgreSQL + MinIO
  - Production-ready configuration

- **Version Information**
  - Version in response headers (`X-Repub-Version`, `X-Repub-Git-Hash`)
  - Version endpoint (`/api/version`)
  - Version displayed in page footer

#### 7. Upstream Package Proxy (Optional)

- **Proxy pub.dev Packages**
  - Cache upstream packages locally
  - Search upstream packages
  - View upstream package details
  - Reduce dependency on pub.dev availability

### Should Have (Future Versions)

#### 1. Package Features
- Package discontinuation with reason/replacement package
- Package version retraction
- Package ownership transfer
- ~~Package statistics (download counts, version popularity)~~ ✅ **Implemented in v1.0** - Dashboard charts show packages created per day and downloads per hour
- Package tags/categories
- Per-package download statistics and detailed analytics
- Download statistics by version and geographic region

#### 2. Enhanced Security
- Two-factor authentication for admin users
- API rate limiting
- Audit logging for all admin actions
- Token expiration policies
- IP whitelisting for admin panel

#### 3. User Experience
- Email notifications (new versions, security alerts)
- RSS/Atom feeds for package updates
- Webhook support for package events
- API documentation with interactive examples
- Package dependency visualization

#### 4. Operations
- Health check endpoint with detailed status
- Prometheus metrics endpoint
- Structured logging with levels
- Database backup/restore tools
- Storage migration tools (SQLite → PostgreSQL, local → S3)

### Won't Have (Explicit Non-Goals)

1. **pub.dev Feature Parity**
   - No package analysis/scoring
   - No static analysis reports
   - No automated quality metrics

2. **Public Registry Features**
   - No mirroring/proxying entire pub.dev registry
   - No package discovery algorithms
   - No community features (likes, comments, ratings)

3. **User Management**
   - No OAuth/SSO integration (self-hosted, package owners only)
   - No organization/team features
   - No user profiles with public packages

## Technical Architecture

### System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Client Applications                  │
│  (dart pub, Flutter projects, web browsers)             │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────┐
│                    Repub Server (Shelf)                  │
├─────────────────────────────────────────────────────────┤
│  API Endpoints  │  Public Web UI  │  Admin Web UI       │
│  (REST API)     │  (Jaspr)       │  (Flutter Web)       │
└─────────────────────────────────────────────────────────┘
                    │                    │
                    ▼                    ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│   Metadata Store         │  │   Blob Store             │
│   (SQLite/PostgreSQL)    │  │   (Local/S3)             │
│   - Packages             │  │   - Package archives     │
│   - Versions             │  │   - Cached packages      │
│   - Users/Tokens         │  │                          │
│   - Admin Users          │  │                          │
│   - Download Analytics   │  │                          │
└──────────────────────────┘  └──────────────────────────┘
```

### Package Structure (Melos Monorepo)

```
repub_model (foundation)
    ↑
repub_auth ← repub_storage
    ↑          ↑
    └──────────┴──→ repub_server ← repub_cli
                         ↑
                         ├──→ repub_web (Jaspr)
                         └──→ repub_admin (Flutter)
```

### Technology Stack

- **Backend**: Dart with Shelf framework
- **Public UI**: Jaspr (Dart web framework with SSR)
- **Admin UI**: Flutter web with BLoC state management
- **Database**: SQLite (default) or PostgreSQL
- **Storage**: Local filesystem (default) or S3-compatible
- **Auth**: Bearer tokens (API) + sessions (web)
- **Build**: Melos for monorepo management
- **Deployment**: Docker with multi-arch support
- **E2E Testing**: chrome-devtools MCP (preferred tool for browser automation and testing)

### Testing Strategy

**Unit Testing**
- Dart test framework for package-level unit tests
- Target: >70% code coverage
- Focus on business logic, models, and storage operations

**Integration Testing**
- API endpoint testing with real database connections
- Package publish/download flow validation
- Authentication and authorization checks

**End-to-End Testing (chrome-devtools MCP)**
- **Preferred Tool**: chrome-devtools MCP for all browser-based E2E tests
- **Why chrome-devtools MCP**:
  - Direct Chrome DevTools Protocol integration for reliable automation
  - Screenshot capabilities for visual regression testing
  - Console error detection for JavaScript issues
  - Network request monitoring for API validation
  - Performance metrics collection (FCP, LCP, CLS)
  - Responsive layout testing across viewport sizes
- **Test Coverage**:
  - Web UI navigation and package browsing
  - Admin UI dashboard and package management
  - User authentication flows (login, registration, logout)
  - Package search and filtering
  - Form validation and error states
  - Visual regression across major viewports (mobile, tablet, desktop)
- **Best Practices**:
  - Always use `fullPage: false` for screenshots to avoid dimension limits
  - Wait after navigation (minimum 1000ms) for JS execution
  - Save large screenshots to filesystem instead of API submission
  - Test multiple viewport sizes for responsive validation
  - Capture console errors and network failures
  - Check for layout issues (horizontal overflow, elements outside viewport)

## User Flows

### Flow 1: Initial Setup (Solo Developer)

1. Pull and run Docker image
2. Container starts with SQLite + local storage
3. Create admin user via CLI
4. Create API token via CLI
5. Add token to `dart pub`
6. Publish first package
7. Access admin UI to view package

### Flow 2: Publishing a Package

1. Developer configures `publish_to` in pubspec.yaml
2. Runs `dart pub publish`
3. Dart CLI requests upload URL (`/api/packages/versions/new`)
4. Server validates token and returns session ID
5. Dart CLI uploads tarball (`/api/packages/versions/upload/:session`)
6. Server validates package structure
7. Dart CLI finalizes publish (`/api/packages/versions/finalize/:session`)
8. Server extracts metadata, stores package, returns success
9. Package appears in web UI and admin dashboard

### Flow 3: Installing a Package

1. Developer adds package to dependencies with hosted URL
2. Runs `dart pub get`
3. Dart CLI requests package metadata (`/api/packages/:name`)
4. Server returns version list
5. Dart CLI resolves version
6. Requests download URL (`/packages/:name/versions/:version.tar.gz`)
7. Server validates auth (if required) and returns archive
8. Dart CLI extracts and caches package

### Flow 4: Admin User Management

1. Admin creates user via CLI: `repub_cli admin create username password`
2. Password is hashed with Argon2
3. Admin logs into admin UI at `/admin/login`
4. Session cookie set (path=/admin, 8-hour TTL)
5. Login attempt logged (IP, user agent, success/failure)
6. Admin can view packages, users, and site stats
7. Admin can view other admin users and their login history
8. Admin cannot create new admin users via UI (security)

### Flow 5: Regular User Registration

1. User visits `/register` page
2. Fills out registration form (email, password, optional name)
3. Password validated (minimum 8 characters)
4. Server creates user with hashed password
5. User redirected to account page
6. Can create personal API tokens for publishing

## API Specification

### Package Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| GET | `/api/packages` | List packages (paginated) | Optional |
| GET | `/api/packages/:name` | Get package info | Optional |
| GET | `/api/packages/:name/versions/:version` | Get version info | Optional |
| GET | `/api/packages/versions/new` | Initiate upload | Required |
| POST | `/api/packages/versions/upload/:session` | Upload package | Required |
| GET | `/api/packages/versions/finalize/:session` | Finalize publish | Required |
| GET | `/packages/:name/versions/:version.tar.gz` | Download package | Optional |

### Admin API Endpoints

| Method | Path | Description | Auth |
|--------|------|-------------|------|
| POST | `/admin/api/auth/login` | Admin login | Public |
| POST | `/admin/api/auth/logout` | Admin logout | Session |
| GET | `/admin/api/auth/me` | Get current admin | Session |
| GET | `/admin/api/stats` | Dashboard stats | Admin |
| GET | `/admin/api/analytics/packages-created` | Packages created per day | Admin |
| GET | `/admin/api/analytics/downloads` | Downloads per hour | Admin |
| GET | `/admin/api/packages/local` | List local packages | Admin |
| GET | `/admin/api/packages/cached` | List cached packages | Admin |
| DELETE | `/admin/api/packages/:name` | Delete package | Admin |
| POST | `/admin/api/packages/:name/discontinue` | Discontinue package | Admin |
| GET | `/admin/api/users` | List regular users | Admin |
| GET | `/admin/api/admin-users` | List admin users | Admin |
| GET | `/admin/api/admin-users/:id/login-history` | View login history | Admin |

### System Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check |
| GET | `/api/version` | Version info |

## Configuration

All configuration via environment variables:

### Core Settings
- `REPUB_LISTEN_ADDR`: Listen address (default: `0.0.0.0:4920`)
- `REPUB_BASE_URL`: Public URL of the registry
- `REPUB_REQUIRE_DOWNLOAD_AUTH`: Require auth for downloads (default: `false`)

### Database
- `REPUB_DATABASE_URL`: SQLite or PostgreSQL connection URL

### Storage
- `REPUB_STORAGE_PATH`: Local storage directory
- `REPUB_S3_ENDPOINT`: S3 endpoint URL (alternative to local storage)
- `REPUB_S3_BUCKET`: S3 bucket name
- `REPUB_S3_ACCESS_KEY`: S3 access key
- `REPUB_S3_SECRET_KEY`: S3 secret key

### Upstream Proxy (Optional)
- `REPUB_ENABLE_UPSTREAM_PROXY`: Enable pub.dev proxy (default: `false`)
- `REPUB_UPSTREAM_URL`: Upstream registry URL (default: `https://pub.dev`)

### Version Info (set by Docker build)
- `REPUB_VERSION`: Version number (e.g., `1.6.13`)
- `REPUB_GIT_HASH`: Git commit hash (e.g., `8c2eab5`)

## Security Considerations

### Authentication

**Admin Authentication (Session-Based)**:
- Admin users managed exclusively via CLI for security
- Separate `admin_session` cookies for admin panel access
- Admin sessions restricted to `/admin` path with `SameSite=Strict`
- Shorter TTL for admin sessions (8 hours vs. 24 hours for users)
- Password hashing with BCrypt (12 rounds)
- No token-based admin access (must use session cookies)

**Regular User Authentication (Dual Mode)**:
- Session-based: Cookie authentication for web UI (`/account`, `/login`, etc.)
- Token-based: Bearer tokens for API operations (publish, download)
- User registration via web UI
- Tokens managed via web UI at `/account/tokens`
- Token hashing with SHA-256 before storage

### Authorization

**Scope-Based Authorization System**:
- All API tokens have associated scopes that define permissions
- Scopes are checked on every protected operation
- Authorization failures return `403 Forbidden` with clear error messages

**Scope Types**:
1. **`admin`**: Full access (all permissions)
   - Use case: Internal automation, admin operations
   - Grants: Publish all, delete, admin panel access (via token + session)

2. **`publish:all`**: Publish any package
   - Use case: CI/CD pipeline for multiple packages
   - Grants: Package publishing only
   - Denies: Delete operations, admin operations

3. **`publish:pkg:<name>`**: Package-specific publishing
   - Use case: Per-package CI/CD tokens
   - Grants: Publish only the specified package
   - Denies: Other packages, delete operations

4. **`read:all`**: Download packages
   - Use case: Private package access when download auth enabled
   - Grants: Package downloads only
   - Denies: All write operations

**Authorization Enforcement Points**:
- `/api/packages/versions/finalize/<sessionId>`: Requires `admin`, `publish:all`, or `publish:pkg:<name>`
- `/admin/api/*`: Requires admin session (cookie-based, not token)
- Package/version deletion: Requires admin session
- Token creation: User session required (users create their own tokens)

**Security Properties**:
- **Principle of Least Privilege**: Tokens can be scoped to minimal required permissions
- **Defense in Depth**: Multiple layers (token validation, scope checking, session validation)
- **Fail Secure**: Missing scopes default to deny
- **Audit Trail**: All token usage logged (last_used_at timestamp)

**Implementation Details**:
- Scopes stored as `TEXT[]` in PostgreSQL, JSON array in SQLite
- Scope checking happens after authentication but before operation execution
- Helper methods in `AuthToken` model: `hasScope()`, `canPublish()`, `canRead()`, `isAdmin`
- Centralized scope enforcement in `repub_auth/src/scopes.dart`

### Backwards Compatibility

- Migration `008_add_default_token_scopes` grants `admin` scope to existing tokens
- Ensures existing deployments continue working after upgrade
- Existing tokens effectively had unlimited access before scope enforcement

### Audit Trail
- All admin login attempts logged (IP, user agent, success/failure, timestamp)
- Failed login attempts tracked separately for security monitoring
- Package operations traceable to users via token ownership
- Token last used timestamp updated on each API call

### Best Practices
- **Token Management**:
  - Create package-specific tokens (`publish:pkg:<name>`) for CI/CD
  - Use `publish:all` only when necessary (multi-package pipelines)
  - Set expiration dates on tokens when possible
  - Revoke tokens immediately if compromised
  - Rotate tokens regularly (quarterly recommended)

- **Deployment Security**:
  - Never commit .env files with credentials or tokens
  - Use strong admin passwords (CLI-managed)
  - Run behind reverse proxy with HTTPS in production
  - Keep Docker images updated for security patches
  - Enable `REQUIRE_DOWNLOAD_AUTH` for private registries

- **Access Control**:
  - Limit admin user count to necessary personnel
  - Use package-specific scopes to limit blast radius
  - Monitor failed login attempts in admin panel
  - Audit token usage via `last_used_at` timestamps

## Success Metrics

### Adoption Metrics
- Docker image pulls
- GitHub stars/forks
- Active deployments (self-reported)

### Quality Metrics
- CI/CD pipeline success rate
- Build time for Docker images
- Zero critical security vulnerabilities
- Test coverage > 70%
- E2E test coverage for critical user flows using chrome-devtools MCP

### User Satisfaction
- GitHub issues resolved within 7 days
- Positive community feedback
- Documentation completeness

## Release Process

### Version Scheme
Semantic versioning: `MAJOR.MINOR.PATCH`

### Automated Release Workflow
1. Developer triggers release workflow (via GitHub Actions)
2. Workflow bumps version (patch/minor/major)
3. Generates categorized changelog from commit messages
4. Creates and pushes git tag
5. Creates GitHub release
6. Builds and pushes multi-arch Docker images
7. Tags Docker images with version + latest

### Commit Convention
- `feat:` - New features (minor version bump)
- `fix:` - Bug fixes (patch version bump)
- `docs:` - Documentation changes
- `chore:` - Maintenance tasks
- `ci:` - CI/CD changes
- `style:` - Code formatting
- `refactor:` - Code refactoring

## Future Roadmap

### v1.1 - Enhanced Admin Experience
- Package discontinuation UI
- User role management
- Bulk package operations
- Export/import functionality

### v1.2 - Developer Tools
- CLI for package management
- Package dependency graph visualization
- Version comparison tools
- Package search improvements

### v1.3 - Enterprise Features
- LDAP/Active Directory integration
- SSO support (SAML, OAuth)
- Multi-tenancy support
- Advanced audit logging

### v2.0 - Platform Expansion
- Support for other package ecosystems (npm, pip, etc.)
- Plugin system for custom extensions
- GraphQL API
- Real-time notifications

## Support & Maintenance

### Documentation
- README.md: Quick start and basic usage
- CLAUDE.md: Development guidelines for AI assistants
- API documentation (OpenAPI spec)
- Deployment guides (Docker, Kubernetes, bare metal)

### Community
- GitHub Issues: Bug reports and feature requests
- GitHub Discussions: Questions and community support
- Discord/Slack: Real-time community chat (future)

### Maintenance Commitments
- Security patches: Within 24 hours
- Bug fixes: Within 1 week
- Feature requests: Prioritized by community votes
- Dependency updates: Monthly

## Appendix

### Glossary
- **Package**: A Dart/Flutter library with a pubspec.yaml
- **Version**: A specific release of a package
- **Token**: Bearer token for API authentication
- **Scope**: Permission level for a token
- **Session**: Temporary authentication for web users
- **Blob Store**: Storage backend for package archives
- **Metadata Store**: Database for package metadata

### References
- [Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md)
- [Dart pub.dev](https://pub.dev)
- [Shelf Framework](https://pub.dev/packages/shelf)
- [Jaspr Framework](https://pub.dev/packages/jaspr)
- [Melos](https://pub.dev/packages/melos)

### Changelog
- **2026-01-27**: Analytics and data visualization
  - Added download tracking system (package_downloads table)
  - Implemented analytics charts in admin dashboard
  - Bar chart: Packages created per day (last 30 days)
  - Line chart: Package downloads per hour (last 24 hours)
  - Added analytics API endpoints for admin dashboard
  - Automatic logging of downloads with IP address and user agent

- **2026-01-27**: Initial PRD created
  - Core features defined
  - Architecture documented
  - Roadmap established
