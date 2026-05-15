# Technical Plan: Security Optimization

## Architecture Overview
The optimizations integrate directly into existing modules:
- `repub_model` (`Config`): Add parsing for `REPUB_TRUSTED_PROXIES`. Add loading/saving mechanisms for the RSA key and AES encryption key.
- `repub_server` (`WebhookService`, `ApiHandlers`): Implement IP resolution for SSRF. Implement trusted proxies validation in `extractClientIp`.
- `repub_storage` (`PostgresMetadataStore`): Change default `SslMode`.
- `repub_migrate`: Move any redundant schema creations out of `repub_storage`.

### Branching Strategy
All development, testing, and implementation for this feature must occur on the dedicated `security-optimization` branch. Ensure that all commits related to these tasks are isolated to this branch before merging into the mainline.

## Technology Choices
- **DNS Resolution for SSRF**: Use `InternetAddress.lookup(host)` in Dart to resolve the IP, validate against the blacklist, then instantiate an `HttpClientRequest` with the IP while explicitly setting the `Host` header to the original domain.
- **Key Persistence**: Default to storing keys in `.encryption_key` and `.rsa_key` files inside a dedicated `REPUB_KEY_PATH` (defaulting to `./data/metadata/keys`). This ensures they survive container restarts when the data directory is mounted.
- **PostgreSQL SSL**: Modify default connection configurations to enforce SSL while providing an explicit override flag (`REPUB_DATABASE_SSL_INSECURE=true`) for compatibility/local dev.

## Component Design
1. **WebhookService**:
    - `_validateWebhookUrl` will become async (`Future<Response?>`) to accommodate DNS resolution.
    - Blacklist check logic will operate on the resolved `InternetAddress`.
2. **PostgresMetadataStore**:
    - Update connection settings to use `SslMode.require` by default.
3. **PasswordCrypto**:
    - Modify the constructor to accept an externally loaded `RSAPrivateKey`.
    - Provide a utility to load/generate and persist the key to disk.
4. **Config**:
    - Parse `REPUB_TRUSTED_PROXIES` into a list of subnets/IPs.
    - Implement logic to load `encryptionKey` from disk if `REPUB_ENCRYPTION_KEY` is not set, generating and saving if necessary.

## Implementation Phases
1. Phase 1: Database SSL & Key Persistence.
2. Phase 2: SSRF DNS Rebinding Protection.
3. Phase 3: Trusted Proxies Implementation.
4. Phase 4: Migration Consolidation.

## Risk Assessment
- **Breaking Changes**: Changing the default `SslMode` may break existing setups that rely on plaintext connections to Postgres. The `REPUB_DATABASE_SSL_INSECURE` override mitigates this.
- **Latency**: DNS resolution in `_validateWebhookUrl` introduces slight latency to webhook creation/delivery, which is an acceptable trade-off for security.

## Open Technical Questions
None.