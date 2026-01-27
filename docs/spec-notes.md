# Pub Repository Spec v2 Implementation Notes

This document describes how repub implements the [Hosted Pub Repository Specification v2](https://github.com/dart-lang/pub/blob/master/doc/repository-spec-v2.md).

## Implemented Endpoints

### Package Info

```
GET /api/packages/<name>
```

Returns:
```json
{
  "name": "package_name",
  "latest": { ... },
  "versions": [
    {
      "version": "1.0.0",
      "pubspec": { ... },
      "archive_url": "http://...",
      "archive_sha256": "...",
      "published": "2024-01-01T00:00:00Z"
    }
  ],
  "isDiscontinued": false,
  "replacedBy": null
}
```

### Publish Flow

#### 1. Initiate Upload

```
GET /api/packages/versions/new
Authorization: Bearer <token>
```

Returns:
```json
{
  "url": "http://localhost:4920/api/packages/versions/upload/<session-id>",
  "fields": {}
}
```

#### 2. Upload Package

```
POST /api/packages/versions/upload/<session-id>
Authorization: Bearer <token>
Content-Type: application/octet-stream

<tarball bytes>
```

Returns:
- 204 No Content
- Location: http://localhost:4920/api/packages/versions/finalize/<session-id>

#### 3. Finalize Upload

```
GET /api/packages/versions/finalize/<session-id>
Authorization: Bearer <token>
```

Returns:
```json
{
  "success": {
    "message": "Successfully published package_name 1.0.0"
  }
}
```

### Download

```
GET /packages/<name>/versions/<version>.tar.gz
```

Returns the raw tarball bytes with `Content-Type: application/gzip`.

## Authentication

All authenticated endpoints require a Bearer token:

```
Authorization: Bearer <token>
```

### Error Responses

**401 Unauthorized** (missing or invalid token):
```json
{
  "error": {
    "code": "unauthorized",
    "message": "..."
  }
}
```

With header:
```
WWW-Authenticate: Bearer realm="pub", message="..."
```

**403 Forbidden** (insufficient scope):
```json
{
  "error": {
    "code": "forbidden",
    "message": "..."
  }
}
```

## Differences from pub.dev

1. **No multipart form upload** - We accept direct binary upload as well as multipart
2. **No analyzer integration** - Packages are stored as-is without analysis
3. **No search** - The `/api/packages` search endpoint is not implemented
4. **Simplified tokens** - No OAuth, just bearer tokens with scopes

## Local Development

### Running Without Docker

1. Start PostgreSQL:
   ```bash
   docker run -d --name pg -e POSTGRES_USER=repub -e POSTGRES_PASSWORD=repub -e POSTGRES_DB=repub -p 5432:5432 postgres:16
   ```

2. Start MinIO:
   ```bash
   docker run -d --name minio -e MINIO_ROOT_USER=minioadmin -e MINIO_ROOT_PASSWORD=minioadmin -p 9000:9000 -p 9001:9001 minio/minio server /data --console-address :9001
   ```

3. Create bucket:
   ```bash
   docker run --rm --network host minio/mc alias set local http://localhost:9000 minioadmin minioadmin
   docker run --rm --network host minio/mc mb local/repub
   ```

4. Run server:
   ```bash
   dart run repub serve
   ```

### Testing with curl

```bash
# Health check
curl http://localhost:4920/health

# Get package info
curl http://localhost:4920/api/packages/my_package

# Create token (via CLI)
dart run repub token create test publish:all

# Initiate upload
curl -H "Authorization: Bearer $TOKEN" http://localhost:4920/api/packages/versions/new
```
