# [ZB41] CI/CD Guide

## Overview
The pipeline runs on GitHub Actions and covers linting, security scanning, deterministic database checks, layered test suites, Docker image build, Kamal-based deployments, smoke validations, and post-deploy monitoring. All commands rely on the same `bin/` entry points used locally.

## Triggers and Branch Policy
- Pull requests → run stages up to `build_image`, produce immutable image but skip deploy.
- Push to `develop` → full pipeline including staging deploy and smoke.
- Push tags `vX.Y.Z` → production deploy after successful image build.
- Workflow dispatch → manual rerun for exceptional cases.
- `main` and `develop` are protected: merge requires a green pipeline.

## Stage Breakdown
1. `prepare` → install Ruby gems, prepare Postgres, assert schema cleanliness.
2. `lint` → `bin/rubocop`, `bin/rails zeitwerk:check`.
3. `security` → `bin/brakeman`, `bundle exec bundle-audit`.
4. `migrations` → full migrate on clean DB + schema diff guard.
5. `test_unit` → `bundle exec rspec --exclude-pattern "spec/requests/**/*_spec.rb"`.
6. `test_integration` → `bundle exec rspec spec/requests`.
7. `build_image` → Docker multi-stage build, push to registry.
8. `deploy_staging` → `bin/kamal deploy --destination staging`.
9. `smoke_staging` → `bin/ci/smoke staging`.
10. `deploy_production` → `bin/kamal deploy --destination production`.
11. `smoke_production` → `bin/ci/smoke production` + rollback hook on failure.
12. `post_deploy_monitoring` → optional external health probe (Prometheus/Loki, etc.).

## Docker Image
- Source: `Dockerfile` (multi-stage, Ruby 3.3 on Alpine).
- Uses Bundler deployment mode, shared for CI and runtime.
- Entry point `bin/docker-entrypoint`, command `bundle exec puma -C config/puma.rb`.
- Build tags: commit SHA by default; release tags reuse same artifact.

## Kamal Configuration
- `config/deploy.yml` defines registry, shared env, destinations `staging` and `production`.
- Hooks call `bin/ci/smoke` after migrations and after rollback.
- Deploy command examples:
  - Staging: `bin/kamal deploy --destination staging --version <sha>`
  - Production: `bin/kamal deploy --destination production --version vX.Y.Z`
- Rollback: `bin/kamal rollback --destination production --version <previous>`

## Smoke Scripts
- `bin/ci/smoke staging|production|local`
- Requires `<ENV>_BASE_URL` secret.
- Checks `/up` and `/recall` (read-only) endpoints.
- Local mode defaults to `http://127.0.0.1:3000`.

## Required Secrets
Configure GitHub Secrets before enabling deploy stages:
- Registry: `REGISTRY_SERVER`, `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`, `REGISTRY_IMAGE`.
- Staging: `STAGING_RAILS_MASTER_KEY`, `STAGING_DATABASE_URL`, `STAGING_SOLID_QUEUE_DATABASE_URL`, `STAGING_SOLID_CACHE_DATABASE_URL`, `STAGING_SOLID_CABLE_DATABASE_URL`, `STAGING_BASE_URL`.
- Production: `PRODUCTION_RAILS_MASTER_KEY`, `PRODUCTION_DATABASE_URL`, `PRODUCTION_SOLID_QUEUE_DATABASE_URL`, `PRODUCTION_SOLID_CACHE_DATABASE_URL`, `PRODUCTION_SOLID_CABLE_DATABASE_URL`, `PRODUCTION_BASE_URL`.
- Monitoring (optional): `MONITORING_URL`.

## Local Equivalents
- Install deps: `bundle config set path vendor/bundle && bundle install`.
- DB prep: `bin/rails db:prepare`.
- Lint: `bin/rubocop`, `bin/rails zeitwerk:check`.
- Security: `bin/brakeman --quiet --no-summary`, `bundle exec bundle-audit check`.
- Tests:
  - Unit: `bundle exec rspec --exclude-pattern "spec/requests/**/*_spec.rb"`.
  - Integration: `bundle exec rspec spec/requests`.
- Docker build parity: `docker build -t memcp:local --target production .`
- Smoke: `STAGING_BASE_URL=https://staging.example.com bin/ci/smoke staging`.

## Migration Rules
- Only safe migrations (CONCURRENT indexes, staged column backfills).
- CI enforces clean `schema.rb`.
- Long backfills move to Solid Queue jobs; release includes deploy + background runbook.
- Update `docs/ci_cd.md` when adding new migration guardrails.

## Release Procedure
1. Merge feature PRs into `develop`.
2. Verify staging deploy + smoke + monitoring.
3. Promote release: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Observe production smoke; watch monitoring dashboards.

## Rollback Procedure
1. Trigger `bin/kamal rollback --destination production --version <previous>`.
2. If migrations were irreversible, execute manual remediation (document in post-mortem).
3. Confirm rollback via `bin/ci/smoke production` and monitoring probes.

## Monitoring & Alerts
- Configure external monitoring endpoint consumed by `MONITORING_URL`.
- Minimum alerts: HTTP 5xx spike, latency (p95), Solid Queue backlog, Postgres locks/long queries.
- Tie alerts to team channel (Slack/Telegram) + escalate when smoke fails in production.

