# Local development setup

This guide walks you from a fresh clone to a running dev server in ~15 minutes.

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Ruby | 3.3.0 | Managed via `rbenv` or `asdf`; the repo includes a `.ruby-version` |
| Bundler | 2.5+ | `gem install bundler` |
| PostgreSQL | 15+ | Must have the `pgvector` extension available (see below) |
| Redis | 7+ | For Sidekiq |
| Node.js | 20+ | For importmap / asset pipeline |
| Foreman | latest | `gem install foreman` — runs Puma + Sidekiq together |

### Installing pgvector

The `code_embeddings` table uses the `vector` type, which requires the `pgvector` extension.

**macOS (Homebrew):**
```bash
brew install pgvector
```

**Ubuntu / Debian:**
```bash
sudo apt install postgresql-15-pgvector
```

**Docker (easiest for development):**
```bash
docker run -d \
  --name ai-dev-toolkit-pg \
  -e POSTGRES_PASSWORD=postgres \
  -p 5432:5432 \
  pgvector/pgvector:pg16
```

Verify it's available:
```sql
psql -c 'CREATE EXTENSION vector;'
-- Should succeed or report "extension already exists"
```

## 1. Clone and bundle

```bash
git clone https://github.com/your-org/ai-dev-toolkit.git
cd ai-dev-toolkit
bundle install
```

## 2. Configure environment variables

Copy the example file:

```bash
cp .env.example .env
```

Then edit `.env` and set at minimum:

```bash
OPENAI_API_KEY=sk-...            # required — get one at platform.openai.com
GITHUB_TOKEN=ghp_...             # required — a Personal Access Token with `repo` scope

DATABASE_URL=postgresql://postgres:postgres@localhost:5432/ai_dev_toolkit_development
REDIS_URL=redis://localhost:6379/0
```

Full list of env vars is documented at the top of `.env.example`.

## 3. Create and migrate the database

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails db:seed       # creates a default admin user (see config/seeds.rb)
```

The first migration (`EnablePgvectorExtension`) runs `CREATE EXTENSION vector`. If it fails with `extension "vector" is not available`, pgvector isn't installed — see the prerequisites section above.

## 4. Run the app

```bash
bin/dev
```

This uses `foreman` + `Procfile.dev` to start three processes:

- `web` — Puma on port 3000
- `worker` — Sidekiq with all three queues (`ai`, `indexing`, `default`)
- `css` — `tailwindcss:watch` for live style rebuilds

Visit <http://localhost:3000>. Log in with the seeded credentials printed by `db:seed`.

## 5. Add your first repository

1. Click **Add Repository** on the dashboard.
2. Enter a `full_name` like `rails/rails` or `your-org/your-private-repo`.
3. The app will validate the repo against GitHub (using your `GITHUB_TOKEN`), then queue a `SyncRepositoryJob` and `IndexRepositoryJob`.
4. Watch progress in the Sidekiq web UI at <http://localhost:3000/sidekiq> (requires an admin user).

For a medium-sized repo (~5k files, ~50k chunks), indexing takes 5-15 minutes and costs ~$0.05 at `text-embedding-3-small` pricing.

## 6. Try the features

Once indexing shows `completed`:

- **Code search**: open the repo's page, use the search box. Try queries like `"where do we handle rate limiting?"` or `"user email validation"`.
- **PR summaries**: pull requests get auto-summarized as they're synced. Hit **Regenerate** on a PR's page to re-run.
- **Natural-language queries**: the dashboard has a query box. Try `"how many PRs were merged in the last 7 days?"` or `"which files have the most embedded chunks?"`.

## Running tests

```bash
bundle exec rspec
```

The test suite is isolated from external services:

- All OpenAI calls are stubbed via **WebMock** + **VCR** cassettes under `spec/vcr_cassettes/`.
- GitHub calls are stubbed the same way.

To record a new VCR cassette (run once with a real API key, then commit):

```bash
VCR_RECORD_MODE=once OPENAI_API_KEY=sk-... bundle exec rspec spec/services/ai/pr_summarizer_spec.rb
```

**Never commit a cassette containing your real API key.** The VCR config in `spec/rails_helper.rb` filters `OPENAI_API_KEY` and `GITHUB_TOKEN` to `<FILTERED>` automatically.

## Troubleshooting

**`PG::UndefinedObject: ERROR: type "vector" does not exist`**
pgvector isn't loaded. Run the first migration explicitly: `bin/rails db:migrate:up VERSION=20250101000001`. If that still fails, the extension isn't installed in your Postgres — see prerequisites.

**`Faraday::ConnectionFailed` hitting OpenAI**
Check `OPENAI_API_KEY` is set and your network can reach `api.openai.com`. Corporate VPNs sometimes MITM TLS in ways ruby-openai doesn't like.

**Sidekiq jobs stuck in `enqueued` forever**
Check the worker process is actually running (`bin/dev` should show `worker.1 started`). If not, `redis-cli ping` should return `PONG`.

**`ActiveRecord::StatementInvalid: PG::QueryCanceled: ERROR: canceling statement due to statement timeout`**
That's the NL-to-SQL safety timeout (5s) doing its job. Either the generated query was pathological or your data is too large for an unindexed scan. Check `query.generated_sql` to see what was attempted.

**Embeddings search returns nothing**
Confirm `repository.indexing_status == "completed"` and `repository.embeddings_count > 0`. If both are fine but results are bad, the HNSW index may not be used — check with `EXPLAIN ANALYZE` on the generated query.
