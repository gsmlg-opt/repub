# Tasks: Security Optimization

## Phase 1: Database SSL & Key Persistence
Shared infrastructure for cryptography and secure database connections.
- [x] [T001] [P] Implement key persistence directory and filesystem helpers in `repub_model` (`Config` and related utils).
- [x] [T002] [P] Refactor `PasswordCrypto` to initialize via persisted `RSAPrivateKey` or generate/save a new one on startup.
- [x] [T003] Update `Config.fromEnv` to manage the AES `encryptionKey` file creation/loading if `REPUB_ENCRYPTION_KEY` is not present in the environment.
- [x] [T004] [P] Modify `PostgresMetadataStore` constructor to default `SslMode` to `require`, adding `REPUB_DATABASE_SSL_INSECURE` as a fallback toggle.

## Phase 2: SSRF DNS Rebinding Protection
Blocking dependencies that resolve the primary SSRF vulnerability.
- [x] [T010] [P] Convert `_validateWebhookUrl` in `WebhookService` to return `Future<Response?>`.
- [x] [T011] Implement `InternetAddress.lookup(host)` inside `_validateWebhookUrl` and use the resolved IP to evaluate the SSRF blacklist.
- [x] [T012] Modify webhook HTTP delivery mechanism to initiate requests to the resolved IP while injecting the original `Host` header.
- [x] [T013] Update tests in `webhook_test.dart` to cover DNS rebinding scenarios.

## Phase 3: Trusted Proxies Implementation
Implement user story: "IP whitelisting only trusts X-Forwarded-For from trusted proxies."
- [x] [T020] [P] Parse `REPUB_TRUSTED_PROXIES` in `repub_model/lib/src/config.dart`.
- [x] [T021] Update `extractClientIp` in `ApiHandlers` to validate the immediate socket IP against the trusted proxy list before accepting `X-Forwarded-For`.
- [x] [T022] Add tests for proxy spoofing and extraction.

## Phase 4: Migration Consolidation
Implement user story: "Developer wants centralized database migrations."
- [x] [T030] Identify internal schema definitions in `repub_storage` and remove duplication.
- [x] [T031] Ensure all migration logic lives exclusively in `packages/repub_migrate/lib/src/migrations.dart`.
- [x] [T032] Verify the migration runner in `repub_cli` and automatic startup migration synchronize correctly against `repub_migrate`.
