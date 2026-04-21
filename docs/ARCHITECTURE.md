# Architecture

This document explains how the AI-Native Developer Toolkit is put together, and the rationale behind the major design decisions. If you're contributing code, read this first.

## Layered overview

```
┌──────────────────────────────────────────────────────────────────┐
│  Browser (Hotwire: Turbo + Stimulus)                             │
└──────────────────────────────────────────────────────────────────┘
                              │  HTTP / Turbo Streams over WebSocket
┌──────────────────────────────────────────────────────────────────┐
│  Rails (Puma)                                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │ Controllers  │  │  ViewCompts  │  │  API::V1 controllers │   │
│  └──────┬───────┘  └──────────────┘  └──────────┬───────────┘   │
│         │                                        │               │
│  ┌──────▼────────────────────────────────────────▼────────────┐  │
│  │                    Service Objects                          │  │
│  │  AI::Client  AI::PRSummarizer                               │  │
│  │  Embeddings::{Chunker,Indexer,SemanticSearch}               │  │
│  │  DatabaseQuery::{SqlValidator,NaturalLanguageExecutor}      │  │
│  │  Github::{Client,SourceFileFilter}                          │  │
│  └──────┬──────────────────────┬────────────────────┬─────────┘  │
│         │                      │                    │             │
│  ┌──────▼──────┐        ┌──────▼────────┐    ┌──────▼──────────┐ │
│  │ ActiveRecord│        │    Sidekiq    │    │  External APIs  │ │
│  │  Models     │        │     Jobs      │    │  OpenAI, GitHub │ │
│  └──────┬──────┘        └───────┬───────┘    └─────────────────┘ │
└─────────┼───────────────────────┼──────────────────────────────-─┘
          │                       │
    ┌─────▼─────┐           ┌─────▼─────┐
    │ Postgres  │           │   Redis   │
    │(+pgvector)│           │           │
    └───────────┘           └───────────┘
```

## Data model

Six tables. The relationships are deliberately shallow — we optimize for read performance, not normalization purity.

```
users ──┬─< repositories ──┬─< pull_requests
        │                  ├─< code_embeddings  ◄── vector(1536), HNSW index
        │                  ├─< code_searches
        │                  └─< queries (also) ─┐
        ├─< queries ────────────────────────────┘
        └─< code_searches
```

### `code_embeddings`

This is the table that matters.

```sql
CREATE TABLE code_embeddings (
  id              bigserial PRIMARY KEY,
  repository_id   bigint NOT NULL,
  file_path       varchar NOT NULL,
  language        varchar,
  commit_sha      varchar NOT NULL,
  chunk_index     integer NOT NULL,
  start_line      integer NOT NULL,
  end_line        integer NOT NULL,
  content         text NOT NULL,
  content_digest  text NOT NULL,   -- SHA256 for dedup
  embedding       vector(1536) NOT NULL,
  token_count     integer,
  metadata        jsonb NOT NULL DEFAULT '{}',
  ...
);

CREATE UNIQUE INDEX idx_code_embeddings_unique_chunk
  ON code_embeddings (repository_id, file_path, chunk_index);

CREATE INDEX idx_code_embeddings_vector_hnsw
  ON code_embeddings USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);
```

**Why HNSW over IVFFlat?** HNSW gives better recall at equivalent latency and doesn't require the extra "train the index" step (`IVFFlat` needs representative data in the table before the index is useful). The tradeoff is larger index size and slower writes — acceptable since writes happen in background jobs, reads are synchronous.

**Why `vector(1536)`?** Matches `text-embedding-3-small`'s output. If you swap to `text-embedding-3-large` (3072-dim) or a Matryoshka-truncated variant, you must migrate the column *and* rebuild the HNSW index. `OPENAI_EMBEDDING_DIMS` in the config is a signal — the actual DB column is static.

**Why `content_digest`?** Idempotent indexing. Re-running the indexer after a single-file change embeds only the new chunks; the rest of the repo is skipped at zero API cost.

## Request flow: semantic search

```
User types query in search box
         ↓
Turbo form POST /repositories/:id/code_searches
         ↓
CodeSearchesController#create
         ↓
Embeddings::SemanticSearch#call(query_text)
  ├─ AI::Client#embed(query_text)       → ~200-400ms
  └─ scope.nearest_neighbors(:embedding, vec, distance: :cosine).limit(10)
                                         → ~50-150ms (HNSW index)
         ↓
Persist CodeSearch row (audit log)
         ↓
Render turbo_stream: turbo_stream.update("results", partial: "code_searches/results")
         ↓
Browser swaps #results in place. No full page reload.
```

Typical end-to-end latency: **350-600ms** on a 100k-chunk index.

## Request flow: NL-to-SQL

This is the one flow where I'd rather be slow than wrong. Every arrow is a checkpoint.

```
User: "how many PRs did alice merge last month?"
         ↓
QueriesController#create
         ↓
Query.create!(status: "pending")
         ↓
DatabaseQuery::NaturalLanguageExecutor#call
  │
  ├─ 1. Build system prompt from SchemaDescriber (curated schema only)
  ├─ 2. AI::Client#chat → generated SQL
  ├─ 3. SqlValidator.validate!(sql)  ← STATIC SECURITY GATE
  │       ├─ strip comments first
  │       ├─ split statements (string-literal aware)
  │       ├─ reject non-SELECT/WITH
  │       ├─ scan forbidden keywords
  │       └─ check table references against allow-list
  │
  ├─ 4. BEGIN
  │     SET LOCAL statement_timeout = 5000
  │     SET LOCAL transaction_read_only = on
  │     [execute SQL, grab first 500 rows]
  │     ROLLBACK              ← always, even for pure SELECT
  │
  └─ 5. AI::Client#chat → plain-English explanation (nice-to-have, non-fatal)
         ↓
Query.update!(status: "completed", generated_sql:, result_rows:, explanation:)
         ↓
Render results table + SQL (shown to user) + explanation
```

See [SECURITY.md](SECURITY.md) for why each checkpoint is there and what happens if it's removed.

## Background job topology

Three Sidekiq queues, each with different characteristics:

| Queue | Jobs | Latency target | Why its own queue |
|---|---|---|---|
| `ai` | `SummarizePullRequestJob` | < 60s per job | OpenAI rate limits — we want to isolate AI load so it can't starve the other queues |
| `indexing` | `IndexRepositoryJob`, `ReindexStaleEmbeddingsJob` | Minutes to hours | Long-running, I/O-bound. Kept separate so it doesn't block fast jobs |
| `default` | `SyncRepositoryJob`, `SyncAllRepositoriesJob` | < 30s per job | GitHub API calls, fast |

Sidekiq runs with `-c 10 -q ai -q indexing -q default` by default (see `Procfile`). Scale workers per-queue in production based on load.

### Idempotency and retries

Every job is designed to be safely retryable:

- `IndexRepositoryJob` — `content_digest` dedup means replays are free
- `SummarizePullRequestJob` — checks `ai_status == "running"` to avoid parallel summaries of the same PR
- `SyncRepositoryJob` — uses `find_or_initialize_by` on `(repository_id, number)`

`ApplicationJob` retries transient OpenAI errors up to 5× with exponential backoff and discards permanent errors (`RecordNotFound`, GitHub 404s).

## Hotwire decisions

- **Turbo Drive** for navigation (no SPA framework)
- **Turbo Streams over WebSocket** for the PR summary updates — when `SummarizePullRequestJob` completes, it broadcasts a `turbo_stream.replace` to `pull_request_#{id}` and anyone on the PR's detail page sees the summary appear
- **Stimulus** for the few interactive elements: query textarea auto-resize, copy-SQL-button, search-results keyboard navigation

No React, no Vue. The complexity budget stays with the AI pipelines where it earns its keep.

## Configuration philosophy

Everything that might change between environments is an env var (see `.env.example`). Everything that might change across the app (model names, embedding dimensions, batch sizes) goes through `Rails.application.config.ai_models` so a single line change upgrades the whole app.

Concretely:

```ruby
# config/initializers/openai.rb
Rails.application.config.ai_models = ActiveSupport::OrderedOptions.new.tap do |m|
  m.chat              = ENV.fetch("OPENAI_CHAT_MODEL", "gpt-4o-mini")
  m.chat_reasoning    = ENV.fetch("OPENAI_CHAT_REASONING_MODEL", "gpt-4o")
  m.embedding         = ENV.fetch("OPENAI_EMBEDDING_MODEL", "text-embedding-3-small")
  m.embedding_dims    = Integer(ENV.fetch("OPENAI_EMBEDDING_DIMS", 1536))
end
```

`chat` is the workhorse (cheap). `chat_reasoning` is only used for PR summarization, where the quality delta is worth the cost.

## What we deliberately *don't* do

- **No RAG chat interface over code.** Retrieval is exposed as search results, not blended into a conversational response. This keeps hallucination risk low and makes every answer debuggable (you can see the retrieved chunks).
- **No agentic loops.** Every AI call is single-shot. If it fails, it fails visibly — no tool-call chains to debug.
- **No vector database service.** `pgvector` in the primary Postgres is enough up to ~10M chunks. We'd rather run one fewer service than squeeze out 2× throughput.
- **No fine-tuned models.** The cost/complexity of maintaining a fine-tune outweighs the quality gain for these use cases, at current base-model quality.

If any of these assumptions break at scale, the service-object boundaries are where you'd swap in an alternative.
