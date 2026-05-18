# Optimization Plan: Repub Package Registry

Based on the architectural and security review, this plan outlines a phased approach to hardening the system and improving its long-term maintainability.

## Phase 1: Critical Security & Integrity (Immediate)

### 1.1 Harden SSRF Protection in Webhooks
- **Problem**: Current string-based blacklisting is vulnerable to DNS rebinding.
- **Action**:
    - Modify `WebhookService` to resolve hostnames to IP addresses before validation.
    - Use the resolved IP for the actual HTTP request while preserving the original `Host` header.
    - Implement a strict IP blacklist check (Private, Loopback, Link-local, etc.) on the resolved IP.

### 1.2 Mandatory Database SSL for PostgreSQL
- **Problem**: Default configuration transmits data in plaintext.
- **Action**:
    - Update `PostgresMetadataStore` to default `SslMode` to `require`.
    - Add a configuration toggle (e.g., `REPUB_DATABASE_SSL_INSECURE=true`) for users who explicitly need to disable it (e.g., local dev).

### 1.3 Fix Password Decryption Fragility
- **Problem**: RSA key pair is ephemeral; server restarts break pending logins.
- **Action**:
    - Implement a mechanism to persist the RSA key pair to the metadata store or a local file (e.g., `/data/keys/password_rsa`).
    - Attempt to load existing keys on startup before generating new ones.

---

## Phase 2: Configuration & Network Robustness (Short-term)

### 2.1 Persistent Storage Encryption Key
- **Problem**: Auto-generated `REPUB_ENCRYPTION_KEY` makes database-stored S3 credentials unreadable after a restart.
- **Action**:
    - Update `Config` to warn or fail if `REPUB_ENCRYPTION_KEY` is not provided in production mode.
    - If auto-generated, persist it to a local file (e.g., `/data/metadata/.encryption_key`) so it survives restarts.

### 2.2 Trusted Proxy Implementation
- **Problem**: Blindly trusting `X-Forwarded-For` allows IP spoofing.
- **Action**:
    - Add `REPUB_TRUSTED_PROXIES` environment variable (comma-separated IPs/CIDRs).
    - Update `extractClientIp` in `ApiHandlers` to only trust forwarding headers if the immediate request source is in the trusted list.

---

## Phase 3: Architectural Cleanup (Medium-term)

### 3.1 Consolidate Migration Logic
- **Problem**: Duplicate migration definitions in `repub_storage` and `repub_migrate`.
- **Action**:
    - Centralize all SQL migration strings into `packages/repub_migrate/lib/src/migrations.dart`.
    - Ensure both `repub_server` (automatic migrations) and `repub_cli` (manual migrations) use the same source of truth.

### 3.2 MetadataStore Interface Refinement
- **Problem**: Growing `MetadataStore` interface creates maintenance overhead.
- **Action**:
    - Group related methods into mixins or sub-services (e.g., `UserMetadata`, `PackageMetadata`, `StatsMetadata`) to improve readability and implementation ease.

---

## Verification Strategy

1.  **Security Tests**: Create specific test cases for DNS rebinding and IP spoofing.
2.  **Persistence Tests**: Verify that S3 storage remains accessible after multiple server restarts with database-backed config.
3.  **Migration Tests**: Ensure both SQLite and PostgreSQL migrations remain synchronized and error-free after refactoring.
