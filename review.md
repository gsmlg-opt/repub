# Project Review: Repub Package Registry

This document provides a comprehensive review of the 'repub' project, focusing on architecture, security, and configuration management.

## 1. Architectural & Structural Review

### 1.1 Package Management & Monorepo Structure
- **Melos Usage**: The project effectively utilizes Melos 7.x to manage a modular monorepo. Dependencies are well-defined, and the workspace bootstrapping process is clear.
- **Internal Dependencies**: `repub_model` acts as a solid foundation with zero internal dependencies, promoting clean separation of concerns.
- **Modularity**: The separation of `repub_storage`, `repub_auth`, and `repub_server` allows for independent scaling and testing of core registry components.

### 1.2 Pub API v2 Implementation
- **Compliance**: The server (`repub_server`) implements the Hosted Pub Repository Specification v2, including the complex upload/finalize flow.
- **Upstream Proxy**: The lazy-caching mechanism for `pub.dev` is a significant feature, allowing the registry to serve as a local cache for external packages.

### 1.3 Data Layer Abstractions
- **Storage Flexibility**: The `MetadataStore` and `BlobStore` abstractions successfully support both SQLite/PostgreSQL and Local/S3 backends.
- **Redundancy Note**: There appears to be some duplication between the `repub_migrate` package and internal migration definitions in `repub_storage`. Consolidating these would reduce maintenance overhead.

### 1.4 Frontend Architecture
- **Dual Approach**: Using Jaspr for the public UI (SEO/speed) and Flutter/BLoC for the admin dashboard (rich interaction) is a sensible architectural choice for their respective use cases.

---

## 2. Security & Configuration Review

| Category | Finding | Severity |
| :--- | :--- | :--- |
| **Auth** | **Ephemeral RSA Key Pair**: `PasswordCrypto` generates a new key on every restart. | **Medium** |
| **Data** | **Default Disabled DB SSL**: PostgreSQL defaults to `SslMode.disable`. | **High** |
| **Network** | **SSRF DNS Rebinding**: Webhook protection uses string checks instead of IP resolution. | **High** |
| **Network** | **Untrusted X-Forwarded-For**: IP extraction trusts headers without proxy verification. | **Medium** |
| **Config** | **Ephemeral Encryption Key**: `REPUB_ENCRYPTION_KEY` is auto-generated if missing. | **Medium** |

### 2.1 Critical Security Vulnerabilities
- **SSRF (High)**: Webhook URL validation is susceptible to DNS rebinding. An attacker could bypass the local/private IP checks by using a domain that switches IPs after the check but before the request.
- **Database Traffic (High)**: The default disabled SSL for PostgreSQL exposes all registry data in transit within the internal network.

### 2.2 Architectural Risks & Pitfalls
- **Password Decryption (Medium)**: Since the RSA key pair for password encryption is ephemeral, any client-side encrypted passwords will fail to decrypt if the server restarts between encryption and transmission.
- **Data Persistence (Medium)**: If `REPUB_ENCRYPTION_KEY` is not fixed, storage credentials encrypted in the database will become unreadable after a server restart, breaking S3 access.

---

## 3. Recommendations & Next Steps

1.  **Harden SSRF Protection**: Resolve hostnames to IPs *once*, validate the IP, and perform the request directly to that IP while injecting the original `Host` header.
2.  **Persistent Encryption Keys**: Require `REPUB_ENCRYPTION_KEY` and the RSA password key pair to be persisted (e.g., via volume mount or secret manager) rather than auto-generated.
3.  **Mandatory DB SSL**: Change the production default for `PostgresMetadataStore` to require SSL.
4.  **Trusted Proxy Config**: Implement a configuration to specify which proxy IPs are trusted to provide the `X-Forwarded-For` header.
5.  **Refactor Migrations**: Centralize all SQL migrations into a single location (likely `repub_migrate`) to ensure consistency between CLI and Server operations.
