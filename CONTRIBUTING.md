# Contributing

Thanks for your interest. The short version:

1. Fork, branch off `main`.
2. Run `bin/setup` — gets you to a working dev environment.
3. Make your change. Keep it focused.
4. Run the full suite: `bundle exec rspec`. It must stay green.
5. Open a PR. Describe what and why.

## Ground rules

**Any new AI pipeline needs WebMock/VCR coverage.** CI doesn't have an OpenAI key. Record cassettes locally with `VCR_RECORD_MODE=once` and commit them — the config filters API keys automatically (verify before pushing).

**Any change to `DatabaseQuery::SqlValidator` needs new adversarial test cases.** If you're relaxing a rule, explain in the PR description why the rule isn't needed. If you're tightening a rule, add cases that prove the old inputs still work.

**Any new table that should be queryable via NL-to-SQL must be added to BOTH `SqlValidator::ALLOWED_TABLES` and `SchemaDescriber::SCHEMA`.** The allow-list is deliberately hand-maintained — don't automate it.

**Migrations must be reversible and additive-first.** For a column rename: add-new + backfill + swap-reads + drop-old over at least two deploys. See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for the zero-downtime rules.

## Code style

- `rubocop-rails` config is authoritative. `bundle exec rubocop -a` before you push.
- Service objects go in `app/services/<namespace>/`. Each has a `.call` (or `#call`) instance entry point.
- Controllers stay skinny — anything more than param munging and a service call belongs in a service.
- Views: no logic beyond simple conditionals. Anything fancier becomes a helper or ViewComponent.

## What makes a good PR

- One thing. Not three things.
- Tests first, or at least in the same diff.
- A short description: what problem, what approach, what you considered and rejected.
- Screenshots for UI changes.
- If it changes behavior visible to operators (new env var, new queue, new migration ordering), update the relevant doc in the same PR.

## Security issues

Don't open a public issue. Email `security@your-domain.example` instead.
