# Feature Specification: Security Optimization

**Status**: Draft
**Created**: 2026-05-15

## Overview
This feature implements a series of critical security and architectural optimizations for the Repub package registry, focusing on hardening the webhook SSRF protection, mandating database SSL, and ensuring persistent cryptographic keys. It mitigates identified vulnerabilities such as DNS rebinding and IP spoofing.

## User Scenarios
1. As an administrator, I want webhooks to be protected against DNS rebinding so that attackers cannot access internal network services.
2. As a system operator, I want PostgreSQL connections to use SSL by default so that database traffic is encrypted in transit.
3. As a system operator, I want password encryption keys and storage configuration keys to be persistent so that server restarts do not lock out users or break S3 access.
4. As an administrator, I want IP whitelisting to only trust the `X-Forwarded-For` header from designated trusted proxies so that IP spoofing is prevented.
5. As a developer, I want all database migrations to be centralized in one package so that the CLI and server stay synchronized.

## Functional Requirements
1. The webhook service must resolve hostnames to IP addresses before validating against the SSRF blacklist.
2. The webhook service must perform the HTTP request using the validated IP address while preserving the original `Host` header.
3. The `PostgresMetadataStore` must default to `SslMode.require`.
4. A mechanism to persist the RSA key pair for password encryption must be implemented.
5. The storage encryption key (`REPUB_ENCRYPTION_KEY`) must be persisted across restarts if auto-generated.
6. The application must support a `REPUB_TRUSTED_PROXIES` environment variable (comma-separated list of IP CIDRs).
7. Client IP extraction must only use `X-Forwarded-For` if the direct incoming request IP matches a trusted proxy.
8. Duplicate migration definitions in `repub_storage` must be removed and centralized in `repub_migrate`.

## Success Criteria
- Webhook tests verify that DNS rebinding to `127.0.0.1` is blocked.
- The server fails to start or connects securely if the database requires SSL.
- S3 configuration remains accessible after multiple server restarts when using an auto-generated encryption key.
- Admin panel remains accessible after a server restart using the previously saved encrypted password.

## Key Entities
- `Config`: Expanded to include trusted proxies.
- `WebhookService`: Updated to perform IP resolution and Host header manipulation.

## Out of Scope
- Complete refactoring of the `MetadataStore` interface.

## Open Questions
- [NEEDS CLARIFICATION] Where exactly should the RSA key and encryption key be persisted by default if no environment variables are provided?
