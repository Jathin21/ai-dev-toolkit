# AI-Native Developer Toolkit

An open-source, AI-powered developer productivity suite built on Rails 7.1, Hotwire, PostgreSQL (with `pgvector`), Sidekiq, and the OpenAI API.

It does three things well:

1. **Automated PR summarization** — every pull request synced from GitHub gets a structured AI summary: plain-English description, reviewer-focused notes, risk level, and affected areas.
2. **Semantic code search** — natural-language queries (`"where do we rate-limit the API?"`) return the most relevant code chunks across indexed repositories, powered by OpenAI embeddings and `pgvector`'s HNSW index.
3. **Natural-language database querying** — ask `"how many PRs did each author merge last month?"` and get back executed SQL, the result rows, and a plain-English explanation.

The goal throughout is **sub-second interactive response** for searches and queries, with heavier work (indexing, summarization) happening asynchronously in Sidekiq.

---

## Quick links

| Doc | Purpose |
|---|---|
| [docs/SETUP.md](docs/SETUP.md) | Local development setup, step by step |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the pieces fit together, and why |
| [docs/API.md](docs/API.md) | JSON API reference |
| [docs/SECURITY.md](docs/SECURITY.md) | Threat model and mitigations (read this before enabling NL-to-SQL in production) |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | Production deployment notes |

---

## Stack

- **Rails 7.1** (Ruby 3.3)
- **PostgreSQL 15+** with the `pgvector` extension
- **Sidekiq 7** on **Redis 7** for background jobs
- **Hotwire** (Turbo + Stimulus) for real-time UI updates, no SPA
- **OpenAI API** via `ruby-openai` (`gpt-4o`, `gpt-4o-mini`, `text-embedding-3-small`)
- **Neighbor** gem for ActiveRecord ↔ pgvector integration
- **Octokit** for GitHub
- **Devise + Pundit** for auth, **Rack::Attack** for rate limiting
- **RSpec + WebMock + VCR** for testing

---

## Features in detail

### PR summarization

When a repository is synced, every pull request (new or updated-since-last-sync) is enqueued into `SummarizePullRequestJob`. The job:

1. Fetches the unified diff from GitHub (capped at 120KB to fit the context window).
2. Sends a JSON-mode chat completion to `gpt-4o` with a carefully-tuned system prompt.
3. Parses the response into `{ summary, review_notes, risk_level, areas, test_coverage }`.
4. Broadcasts a Turbo Stream update so anyone watching the PR's detail page sees the summary appear without refreshing.

The summary is stored on the `PullRequest` record (`ai_summary`, `ai_review_notes`, `ai_metadata`) and is idempotent — re-running is safe and doesn't duplicate content.

### Semantic code search

Indexing pipeline:

1. `IndexRepositoryJob` walks the repo's default-branch tree via the GitHub Trees API.
2. Files are filtered to a language allow-list (30+ extensions) and skip-list (`node_modules`, lockfiles, minified assets, etc.).
3. Each file is chunked by `Embeddings::Chunker` — line-oriented, 500-token budget, 1-line overlap between chunks.
4. Chunks are **deduped by SHA256**: if a `(repository_id, file_path, chunk_index)` row already has the same content digest, we skip the embedding API call entirely. Re-indexing a 10k-file repo after a 3-file change costs pennies.
5. Embeddings are generated in batches of 96 and upserted via `insert_all` with `on_conflict` — atomic per batch.

Query pipeline:

1. User's natural-language query is embedded (`text-embedding-3-small`, 1536 dimensions).
2. `pgvector`'s HNSW index (cosine distance) returns the top-*k* nearest neighbors in ~50-150ms on a 100k-chunk corpus.
3. Results include file path, line range, similarity score, and a preview snippet.

### Natural-language database queries

This is the riskiest feature, so it has the most defense in depth:

1. **Curated schema** — the LLM sees only 5 allow-listed tables, with a hand-picked column list. It never learns that `users.encrypted_password` exists.
2. **Generated SQL is statically validated** by `DatabaseQuery::SqlValidator` before it goes near the database:
   - Comments (`--`, `/* */`) are stripped *first*, so `/* DROP TABLE */ SELECT 1` doesn't fool the keyword scanner.
   - Stacked statements (multiple `;`-separated queries) are rejected, with proper string-literal awareness.
   - A forbidden-keyword list blocks any mutation: `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `DROP`, `ALTER`, `CREATE`, `GRANT`, `EXECUTE`, `COPY`, `SET`, etc.
   - Only tables on the allow-list may appear after `FROM`/`JOIN`.
3. **Execution happens inside a rolled-back transaction** with `SET LOCAL statement_timeout = 5000` and `SET LOCAL transaction_read_only = on`. A runaway cross-join can't take the DB down, and even a validated SELECT can't leave side effects.
4. **Results are capped at 500 rows** and normalized (dates to ISO-8601, BigDecimal to Float) before being stored as JSONB on the `queries` record.
5. **A plain-English explanation** is generated from the SQL + first 5 rows, but its failure never fails the query itself.

See [docs/SECURITY.md](docs/SECURITY.md) for the full threat model.

---

## Roadmap

- [ ] Git provider abstraction (GitLab, Bitbucket, self-hosted Gitea)
- [ ] Multi-model support (Anthropic Claude, local Ollama)
- [ ] Inline review comments posted back to GitHub
- [ ] Slack notifications for high-risk PRs
- [ ] Per-repository embedding model overrides (Code-specific models for code-heavy repos)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: fork, branch, `bin/rspec`, open a PR. The test suite must stay green and any new AI pipeline needs WebMock/VCR coverage so CI doesn't depend on OpenAI uptime.

## License

MIT. See [LICENSE](LICENSE).
