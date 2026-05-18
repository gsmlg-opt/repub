# Repub Constitution

## Core Principles

### I. Security First
All features must prioritize security. Specifically, SSRF protections must resolve hostnames to IPs, DB connections must use SSL by default, and cryptographic keys must be persistent.

### II. Local/Self-Hosted Orientation
The system is designed for self-hosting. External dependencies for core operations should be minimized. Default configurations should work out-of-the-box via SQLite and local storage, but must securely support PostgreSQL and S3.

### III. Modular Architecture
Features must respect the existing package boundaries: `repub_model` for domain logic, `repub_auth` for security, `repub_storage` for data, and `repub_server` for API handlers.

### IV. Spec-Driven Development
All complex modifications must follow the SDD workflow (`spec.md` -> `plan.md` -> `tasks.md`) and address architectural risks before implementation.

**Version**: 1.0.0 | **Ratified**: 2026-05-15 | **Last Amended**: 2026-05-15