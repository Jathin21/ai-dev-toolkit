# JSON API

All endpoints are under `/api/v1/` and require authentication via a session cookie (same as the web UI) or a Bearer token. Responses are JSON. Errors use standard HTTP status codes with a `{ "error": "..." }` body.

## Authentication

The API uses the same Devise session as the web UI. For machine-to-machine access, create an API token via the user settings page and pass it as `Authorization: Bearer <token>`.

## Rate limits

Enforced by `Rack::Attack`:

- **30 requests/minute** for AI-heavy endpoints (`/code_searches`, `/queries`, `/pull_requests/:id/summarize`)
- **300 requests/5 minutes** general per-IP limit

Exceeding a limit returns `429 Too Many Requests` with `RateLimit-*` response headers.

---

## Repositories

### `GET /api/v1/repositories`

List the authenticated user's repositories.

**Response `200`:**
```json
{
  "repositories": [
    {
      "id": 1,
      "full_name": "rails/rails",
      "indexing_status": "completed",
      "embeddings_count": 48_291,
      "pull_requests_count": 127,
      "last_indexed_at": "2026-04-19T22:14:03Z"
    }
  ]
}
```

### `GET /api/v1/repositories/:id`

Full detail for one repo.

**Response `200`:**
```json
{
  "repository": {
    "id": 1,
    "full_name": "rails/rails",
    "owner": "rails",
    "name": "rails",
    "default_branch": "main",
    "indexing_status": "completed",
    "last_synced_at":  "2026-04-20T09:00:00Z",
    "last_indexed_at": "2026-04-19T22:14:03Z",
    "embeddings_count": 48291,
    "pull_requests_count": 127
  }
}
```

**Errors:**
- `404` — repository not found or not owned by the requesting user

---

## Pull requests

### `GET /api/v1/repositories/:repository_id/pull_requests`

List pull requests for a repo.

**Query params:**
- `state` — one of `open`, `closed`, `merged`
- `page`, `per_page` — pagination (default `per_page=25`, max `100`)

**Response `200`:**
```json
{
  "pull_requests": [
    {
      "id": 12,
      "number": 48291,
      "title": "Fix race condition in ActiveRecord connection pool",
      "state": "merged",
      "author_login": "alice",
      "ai_status": "completed",
      "additions": 42,
      "deletions": 18,
      "changed_files": 3,
      "pr_merged_at": "2026-04-18T14:22:00Z"
    }
  ],
  "page": 1,
  "total_pages": 6
}
```

### `GET /api/v1/repositories/:repository_id/pull_requests/:id`

Full PR detail including AI summary.

**Response `200`:**
```json
{
  "pull_request": {
    "id": 12,
    "number": 48291,
    "title": "...",
    "body": "...",
    "state": "merged",
    "ai_status": "completed",
    "ai_summary": "This PR fixes a race condition in the connection pool by wrapping...",
    "ai_review_notes": "- Verify the new mutex doesn't introduce contention under load\n- Consider adding a benchmark",
    "ai_metadata": {
      "risk_level": "medium",
      "areas": ["activerecord", "concurrency"],
      "test_coverage": "Good — includes a regression test that reliably reproduces the race"
    },
    "ai_generated_at": "2026-04-18T14:25:12Z"
  }
}
```

### `POST /api/v1/repositories/:repository_id/pull_requests/:id/summarize`

Enqueue (or re-enqueue) an AI summary. Returns immediately; check `ai_status` to poll.

**Response `202`:**
```json
{ "ai_status": "pending", "job_id": "b7a3..." }
```

---

## Code search

### `POST /api/v1/repositories/:repository_id/code_searches`

Semantic search over indexed code.

**Request:**
```json
{
  "query":    "where do we rate-limit API requests?",
  "limit":    10,
  "language": "ruby"          // optional filter
}
```

**Response `200`:**
```json
{
  "query": "where do we rate-limit API requests?",
  "execution_ms": 412,
  "results": [
    {
      "file_path":  "config/initializers/rack_attack.rb",
      "language":   "ruby",
      "start_line": 1,
      "end_line":   23,
      "similarity": 0.8421,
      "preview":    "class Rack::Attack\n  throttle(\"ai_requests/ip\", limit: 30, period: 1.minute) do |req|\n    ..."
    }
  ]
}
```

**Errors:**
- `400` — `query` missing or blank
- `409` — repository not yet indexed (`indexing_status != "completed"`)
- `429` — rate limit exceeded

---

## Natural-language database queries

### `POST /api/v1/repositories/:repository_id/queries`

Ask a natural-language question. The server generates SQL, validates it, executes it read-only, and returns rows plus an explanation.

`repository_id` scopes the query for UI purposes; the generated SQL itself can only touch the 5 allow-listed tables.

**Request:**
```json
{
  "question": "how many PRs did each author merge in the last 30 days?"
}
```

**Response `200`:**
```json
{
  "query": {
    "id": 88,
    "status": "completed",
    "question": "how many PRs did each author merge in the last 30 days?",
    "generated_sql": "SELECT author_login, COUNT(*) AS merged_count\nFROM pull_requests\nWHERE state = 'merged' AND pr_merged_at > NOW() - INTERVAL '30 days'\nGROUP BY author_login\nORDER BY merged_count DESC\nLIMIT 100",
    "result_columns": ["author_login", "merged_count"],
    "result_rows": [
      ["alice", 14],
      ["bob",    9],
      ["carol",  7]
    ],
    "row_count": 3,
    "execution_ms": 47,
    "explanation": "Alice merged the most PRs in the last month (14), followed by Bob (9) and Carol (7)."
  }
}
```

**Response `422` (query rejected by security validator):**
```json
{
  "query": {
    "id": 89,
    "status": "rejected",
    "error_message": "Forbidden keyword detected: DROP"
  }
}
```

**Response `500` (runtime error, e.g. statement timeout):**
```json
{
  "query": {
    "id": 90,
    "status": "failed",
    "error_message": "PG::QueryCanceled: ERROR: canceling statement due to statement timeout"
  }
}
```

---

## Common response fields

Every resource includes `created_at` and `updated_at` in ISO-8601 UTC. Numeric IDs are bigints serialized as JSON numbers; be cautious deserializing in languages with 32-bit int defaults.

## Versioning

The `/api/v1/` prefix is a promise of stability. Breaking changes ship under `/api/v2/`. Additive changes (new fields on existing responses, new endpoints) may appear in `v1` without notice.
