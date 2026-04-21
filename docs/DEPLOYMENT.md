# Deployment

This guide covers the main considerations for running the app in production. Specific platform recipes (Fly.io, Render, Heroku, Kubernetes) are at the bottom.

## Production checklist

Before going live:

- [ ] **Postgres with pgvector** — not all managed Postgres offerings include pgvector. Confirm before committing to a provider. See "Platform notes" below.
- [ ] **Redis** for Sidekiq. Needs persistence (`appendonly yes`) so in-flight jobs survive restarts.
- [ ] **Read-only DB role** created and wired to `DATABASE_QUERY_URL` (see [SECURITY.md](SECURITY.md)).
- [ ] **Environment variables** set: `OPENAI_API_KEY`, `GITHUB_TOKEN` (or per-user tokens), `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY_BASE`, `RAILS_MASTER_KEY`.
- [ ] **SSL** terminated at the load balancer or via Rails (`config.force_ssl = true` is on by default in production).
- [ ] **Admin user** created with `bin/rails 'users:make_admin[you@example.com]'` so you can access `/sidekiq`.
- [ ] **Error tracking** wired up (Sentry, Honeybadger, Rollbar — pick one and set its env var).
- [ ] **Backups** — at least daily `pg_dump`, retained off-site.

## Scaling guidance

The app has three distinct workloads with different scaling profiles:

| Workload | Bottleneck | Scale by |
|---|---|---|
| Web requests (dashboard, search, NL queries) | Postgres CPU (HNSW search) | Puma threads + Postgres instance size |
| AI summarization | OpenAI API rate limits, not CPU | Sidekiq workers on the `ai` queue + OpenAI tier upgrade |
| Repository indexing | OpenAI embeddings API throughput | Sidekiq workers on the `indexing` queue |

A reasonable starting configuration for ~50 active users:

- 2× web dynos (Puma, `WEB_CONCURRENCY=2`, `RAILS_MAX_THREADS=5`)
- 1× worker dyno (`sidekiq -c 10 -q ai,3 -q indexing,2 -q default,5`)
- Postgres: 4GB RAM, 2 vCPU (with `shared_buffers=1GB`, `work_mem=32MB`)
- Redis: 256MB with AOF persistence

Scale horizontally from there. The app is stateless; session storage is cookie-based; background jobs are idempotent.

### Postgres tuning for pgvector

The HNSW index likes memory. A few settings that matter:

```ini
# postgresql.conf
shared_buffers       = 25% of RAM
work_mem             = 32MB            # per-query working memory
maintenance_work_mem = 256MB           # speeds up HNSW index builds
effective_cache_size = 50% of RAM
```

At query time, HNSW search quality is controlled by `hnsw.ef_search` (default 40). For higher recall:

```ruby
ActiveRecord::Base.connection.execute("SET LOCAL hnsw.ef_search = 80")
```

Higher `ef_search` → better recall, slower queries. 80 is a good compromise for our workload; raise to 120-200 if you find search results missing obvious matches.

## Cost estimation

Approximate monthly cost for 50 developers, 10 repos averaging 5k files each, 200 PRs/month:

| Item | Cost |
|---|---|
| OpenAI embeddings — initial indexing of 500k chunks × 500 tokens × $0.02/1M | ~$5 one-time |
| OpenAI embeddings — re-indexing (only changed chunks, maybe 5%/month) | ~$3/mo |
| OpenAI embeddings — query embeddings (5k searches/mo × ~20 tokens) | <$0.01/mo |
| OpenAI chat — PR summaries (200 PRs × ~5k tokens × gpt-4o @ $5/1M input, $15/1M output) | ~$15/mo |
| OpenAI chat — NL-to-SQL (1k queries/mo × ~2k tokens × gpt-4o-mini) | ~$1/mo |
| Postgres (managed, 4GB/2vCPU) | ~$50/mo |
| Redis (managed, 256MB) | ~$15/mo |
| Web + worker hosting | ~$30-60/mo |
| **Total** | **~$115-150/mo** |

The AI line items scale linearly with activity. The infra line items don't. For most teams, infrastructure dominates the bill up to ~500 active users.

## Platform notes

### Fly.io

pgvector is available in Fly's Postgres via the `pgvector/pgvector` image. See `fly.toml` in the repo (if present) for a starting configuration. Use `fly ssh console -C "bin/rails db:migrate"` for migrations.

### Render

Render's managed Postgres supports pgvector. Enable it via the dashboard. Configure the worker as a separate Background Worker service pointing at the same repo with `bundle exec sidekiq -C config/sidekiq.yml` as the start command.

### Heroku

Heroku Postgres (Standard tier and up) supports pgvector. On the hobby-dev tier it may not be available — upgrade before attempting to migrate.

```bash
heroku addons:create heroku-postgresql:standard-0
heroku addons:create heroku-redis:premium-0
heroku pg:psql -c "CREATE EXTENSION vector"
heroku run bin/rails db:migrate
```

### Self-hosted (Kubernetes / Docker Compose)

A basic Compose file:

```yaml
services:
  postgres:
    image: pgvector/pgvector:pg16
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes: [pgdata:/var/lib/postgresql/data]

  redis:
    image: redis:7-alpine
    command: redis-server --appendonly yes
    volumes: [redisdata:/data]

  web:
    build: .
    command: bin/rails server -b 0.0.0.0
    env_file: .env.production
    depends_on: [postgres, redis]
    ports: ["3000:3000"]

  worker:
    build: .
    command: bundle exec sidekiq
    env_file: .env.production
    depends_on: [postgres, redis]

volumes: { pgdata: {}, redisdata: {} }
```

Build once, tag, ship to your registry. For Kubernetes, convert via `kompose` or write your own manifests.

## Zero-downtime deploys

The app tolerates rolling deploys because:

- Migrations are designed to be additive and reversible (always add columns nullable first, backfill, then add the NOT NULL in a follow-up migration).
- Background jobs are idempotent — an old worker picking up a job queued by new-code is safe.

The one trap: changing `OPENAI_EMBEDDING_DIMS` is not a rolling-deploy-safe operation. The `vector(N)` column size must match exactly, so a model swap requires a coordinated migration + reindex. Don't do it during business hours.

## Monitoring

Log-level basics:

- `ActiveSupport::Notifications` events are emitted for every `AI::Client` call (subscribe in an initializer to ship to your APM).
- Sidekiq job runtimes are visible in the Sidekiq web UI at `/sidekiq`.
- Postgres slow-query logging (`log_min_duration_statement = 500ms`) catches regressions in HNSW search.

Key metrics to alert on:

- `ai_requests.rate_limited` — hitting OpenAI rate limits means the `ai` queue is backed up
- `queries.rejected` rate — a spike can indicate prompt injection attempts or a regression in SQL generation quality
- Sidekiq `default` queue latency > 60s — sync jobs are falling behind
- Postgres connection count approaching pool limit

## Upgrading

Follow Rails' standard upgrade advice. Additional things to watch:

- `ruby-openai` occasionally changes response shapes; pin the version and upgrade deliberately.
- `neighbor` and `pgvector` have a coupled version matrix — check the neighbor gem's README before upgrading either.
- `tiktoken_ruby` needs the right encoding for newer OpenAI models; if token counting drifts, update the gem.
