# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project Constitution

CRITICAL CONSTRAINTS (read these before every task):
- The client auth token are not mandatory, we are a self-hosted project, that only use by the package owner themself.
- Do not add SSL support because this project will live after a reverse proxy server.
- Do not change default listen address in development mode.

## Build & Development Commands

```bash
# Bootstrap workspace (run first)
melos bootstrap

# Development - unified server on port 8080 with hot reload
# Access everything at http://localhost:8080 (API + web UI)
melos run dev

# Run API server only (SQLite + local storage, no external deps)
melos run server

# Build production binary
melos run build

# Build web UI for production
melos run build:web

# Quality checks
melos run analyze          # Static analysis with fatal-infos
melos run format           # Format all Dart files
melos run format:check     # Check formatting without changes
melos run test             # Run tests in all packages

# Database migrations
melos run migrate
```

## Architecture

Melos-managed monorepo implementing the [Hosted Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md).

### Package Dependency Graph

```
repub_model (foundation - shared domain models)
    ↑
repub_auth ← repub_storage
    ↑          ↑
    └──────────┴──→ repub_server ← repub_cli
                         ↑
                    repub_web (Jaspr framework)
```

### Packages

| Package | Purpose |
|---------|---------|
| `repub_model` | Domain models: Package, PackageVersion, AuthToken, Config |
| `repub_auth` | Bearer token authentication, scope checking |
| `repub_storage` | Database abstraction (SQLite/PostgreSQL) + blob storage (local/S3) |
| `repub_migrate` | SQL schema migrations |
| `repub_server` | HTTP API using Shelf framework |
| `repub_cli` | Admin CLI for tokens, migrations, server startup |
| `repub_web` | Web UI using Jaspr framework |

### Storage Backends

- **Database**: SQLite (default, zero-config) or PostgreSQL
- **Blob Storage**: Local filesystem (default) or S3-compatible (MinIO, AWS S3)
- **Configuration**: All via environment variables (see README.md)

### Key Entry Points

- `packages/repub_server/bin/repub_server.dart` - Production server
- `packages/repub_server/bin/repub_dev_server.dart` - Development server (unified port)
- `packages/repub_cli/bin/repub_cli.dart` - Admin CLI
- `packages/repub_server/lib/src/handlers.dart` - API route handlers
- `packages/repub_storage/lib/src/metadata.dart` - Database operations
- `packages/repub_storage/lib/src/blobs.dart` - Blob storage operations
- `packages/repub_web/lib/app.dart` - Web UI routes

### Development Server

The dev server (`repub_dev_server.dart`) provides a unified development experience on port 8080:
- **API routes** (`/api/*`, `/packages/*`, `/health`) - Handled directly by the server
- **Web UI** (all other routes) - Proxied to webdev on port 8081 for hot reload
- Users only access `http://localhost:8080` for everything
- Web changes reload instantly via webdev's hot reload mechanism

### Token Scopes

| Scope | Access |
|-------|--------|
| `admin` | Full access including admin panel |
| `publish:all` | Publish any package |
| `publish:pkg:<name>` | Publish specific package only |
| `read:all` | Read/download (when download auth required) |

## Environment Variables

Core settings: `REPUB_LISTEN_ADDR`, `REPUB_BASE_URL`, `REPUB_REQUIRE_DOWNLOAD_AUTH`

Database: `REPUB_DATABASE_URL` (sqlite:./path or postgres://...)

Storage: Either `REPUB_STORAGE_PATH` (local) or S3 vars (`REPUB_S3_ENDPOINT`, `REPUB_S3_ACCESS_KEY`, `REPUB_S3_SECRET_KEY`, `REPUB_S3_BUCKET`)

## Docker

```bash
# Standalone (SQLite + local storage)
docker run -p 8080:8080 -v repub_data:/data ghcr.io/gsmlg-dev/repub:latest

# With PostgreSQL + MinIO
docker compose up -d
```
