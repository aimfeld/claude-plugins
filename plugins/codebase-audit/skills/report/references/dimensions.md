# Dimensions Reference

For each of the 16 dimensions, this file lists: what to look for, which probes to run, common evidence patterns, and what pushes the grade up or down.

Read only the sections for dimensions you're currently assessing. You do not need to load this file upfront.

---

## 1. Architecture & layering

**Question:** Is there a clear convention for where logic lives, and is it followed everywhere or just in the files someone showed off?

**Probes:**
- Read `CLAUDE.md` / `ARCHITECTURE.md` / `docs/architecture.md` for stated conventions.
- Glob the top-level source directories. Count folders at each layer (routers vs services vs repositories, or controllers vs models vs views, or handlers vs use-cases vs adapters).
- Pick one representative file per layer and check that it does what the layer name implies.
- Grep for anti-patterns: SQL in controllers, HTTP status codes in repositories, business logic in ORM models.

**Pushes grade up:**
- Convention documented in CLAUDE.md/README and followed in every spot-check.
- Shared utilities for cross-cutting concerns (filters, auth dependencies, error formatters).
- Pure-function domain logic that is unit-testable without a DB or HTTP context.

**Pushes grade down:**
- Business logic in ORM models or controllers.
- "God files" > 1,000 LOC with mixed concerns.
- Inconsistent layering — some features follow the convention, others don't.
- No stated convention AND no visible consistency.

---

## 2. Code duplication

**Question:** Is core logic defined in one place and reused, or copy-pasted into N callers?

**Probes:**
- Grep for repeated function names or near-identical signatures across files.
- For known cross-cutting concerns (query filters, auth checks, date formatting, error responses), check whether there's a single utility.
- Count import sites of shared utilities — "imported from `query_utils` in 6 repositories" is strong evidence.

**Pushes grade up:**
- A named shared module with a clear count of callers.
- Explicit comment or doc saying "single source of truth".

**Pushes grade down:**
- Same string literal or regex repeated in 3+ files.
- Copy-pasted error response shapes.
- Duplicated validation rules between frontend and backend without a schema generator.

---

## 3. Error handling & Sentry/observability coverage

**Question:** When something goes wrong, will the maintainer know, and will they have enough context to debug?

**Probes:**
- Grep for `capture_exception`, `Sentry.captureException`, `logger.error`, `panic`, `rescue`. Count sites. Divide by total LOC for a rough density.
- Grep for bare `except:` / `catch (e)` / `catch { }` — any found should be called out.
- Check retry loops: do they capture on every attempt (noisy) or only the final failure (correct)?
- Check whether error messages embed variable data (fragments Sentry grouping) vs use `set_context` / `set_tag`.
- Frontend: global error handlers on `QueryCache`, `MutationCache`, `window.onerror`, `unhandledrejection`.

**Pushes grade up:**
- `before_send` hook that fingerprints noisy known errors (DB connection drops, timeouts).
- Context/tags attached before capture.
- Retry loops capture on last attempt only.
- Zero bare excepts.

**Pushes grade down:**
- Bare `except:` or `catch (e) { /* ignore */ }`.
- Error messages like `f"Failed for user {user_id}"` that fragment grouping.
- No global frontend error handler.
- Errors swallowed and logged to a DB/console but not captured to an alerting system.

---

## 4. Secrets & configuration

**Question:** Is there anything in the repo that should be rotated?

**Probes:**
- `git grep` for common secret patterns: `API_KEY`, `SECRET_KEY`, `PASSWORD`, `TOKEN`, `AWS_`, `sk-`, `xoxb-`, `ghp_`, `-----BEGIN`, `postgres://`, `mysql://`. **Exclude `reports/`, `.planning/`, `docs/`, `.claude/`, and `.idea/`** from these greps — the report this skill writes lives in `reports/`, and prior reports will contain literal pattern strings that self-match on re-runs. Use `--exclude-dir=reports --exclude-dir=.planning --exclude-dir=docs --exclude-dir=.claude --exclude-dir=.idea` (or the `git grep` equivalent).
- Check `.env*` files are in `.gitignore` and not tracked (`git ls-files | grep -E '\.env'`).
- Look for the config loader (e.g., Pydantic `BaseSettings`, `dotenv`, `viper`, `node-config`). Confirm defaults are placeholders (`change-me`, `localhost`) not real values.
- Check `Dockerfile` for `ARG`-baked credentials, `ENV` with real values.
- Check CI config for plaintext secrets vs `${{ secrets.X }}` references.

**Pushes grade up:**
- All secrets sourced from env vars with obvious placeholder defaults.
- `.env` in `.gitignore`, not tracked, `.env.example` present as the contract.
- CI uses secret-store references only.

**Pushes grade down:**
- A real-looking key literal in any tracked file.
- `.env` committed.
- Dockerfile bakes credentials at build time.

If you find anything that could be a real secret, redact it in the report (`<REDACTED: pattern match>`) and flag it as immediate-action.

---

## 5. Code smells

**Question:** Is the codebase living in the present, or are there ghost rooms?

**Probes:**
- Grep for `TODO`, `FIXME`, `XXX`, `HACK`, `DEPRECATED`. Count and spot-check.
- Look for commented-out code blocks (lines starting with `//` or `#` that are clearly code). A small script: count consecutive comment lines that contain `(`, `=`, `;`.
- Check for magic numbers in decision logic: grep for comparisons to numeric literals that aren't 0/1 (`if (x > 42)`, `if x < 3600`). Each magic number should ideally be a named constant.
- Dead imports / unused exports: if the language has a detector (knip, ts-unused-exports, vulture, unused in Rust), check CI for it.

**Pushes grade up:**
- Zero or very few TODO/FIXME/XXX.
- Magic numbers extracted to named constants with rationale comments.
- Dead-export detection runs in CI.

**Pushes grade down:**
- 20+ TODOs, especially ones older than 6 months.
- Large commented-out code blocks.
- Named constants missing from obvious thresholds and timeouts.

---

## 6. Maintainability & tests

**Question:** Can someone who is not the author land a change safely?

**Probes:**
- Count test files and test LOC (from the stats script).
- Identify the test framework (pytest, vitest, jest, go test, RSpec, JUnit).
- Real DB vs mocks: grep for `docker compose` / `testcontainers` / `postgres` in `conftest.py` / `jest.setup.ts` / CI workflow.
- Coverage: if the stats script found a coverage artifact, read it.
- CI gates: list what runs in `.github/workflows/*.yml` (or `.circleci/config.yml`, `.gitlab-ci.yml`). Lint, type check, dead-export detection, tests, build.
- Migration discipline (if DB): count migrations, spot-check that `downgrade()` is non-trivial and destructive transitions carry explicit casts.

**Pushes grade up:**
- Test LOC ≥ 50% of code LOC for service-oriented projects.
- Integration tests run against real DB (or a container) in CI.
- Multi-gate CI (lint + type check + dead-export + tests).
- Migrations have working downgrades.

**Pushes grade down:**
- Test LOC < 10% of code LOC for production systems.
- Only mocks, no integration path.
- No type checker in CI for a project in a type-checkable language.
- Migrations without downgrade or with empty downgrade.

---

## 7. Security

**Question:** Would a reviewer with a security hat on flag anything?

**Probes:**
- Auth dependencies: find the auth middleware / dependency. Grep for routes that should require auth but don't declare the dependency.
- SQL: grep for f-string / concatenation into `execute()` / `query()` / `raw()`. Any finding is immediate-action.
- ORM usage: is every query going through the ORM or query builder?
- CORS: check for `allow_origins=["*"]` or equivalent in production config.
- CSRF / OAuth state: if OAuth is present, check the state-parameter handling. Is `secrets.token_urlsafe` / `crypto.randomUUID` used? Is the state validated on callback?
- Input validation at boundaries: Pydantic / Zod / express-validator / Joi / strong types on HTTP input.
- PII handling: is there a `send_default_pii=False` on Sentry, or equivalent?
- Password hashing: bcrypt/argon2 via framework, not SHA-based.
- Rate limiting: check for middleware (slowapi, express-rate-limit, nginx-level).
- Known-CVE patches: look for inline comments citing CVEs as evidence the team tracks them.

**Pushes grade up:**
- 100% ORM / query builder, zero raw SQL.
- Auth dependency applied uniformly.
- PII-off on Sentry.
- CSRF protection for state-changing endpoints.

**Pushes grade down:**
- Any raw SQL with string interpolation.
- Missing auth on a state-changing route.
- CORS `*` in production.
- Rate limit absent on signup or third-party integrations.

---

## 8. Database design

**Question:** Is the schema designed to prevent bad data or to accept it and hope?

**Probes:**
- **Where are FK constraints actually enforced — DB or ORM?** Check *both* layers before concluding the schema is lax. The DB layer is the source of truth:
  - **DB-level first** — read migration files (Alembic, phinx, Flyway, Liquibase, Rails, Prisma, Knex, goose, Django migrations) and any `schema.sql` / `structure.sql` / `*.dbml`. Grep for `FOREIGN KEY`, `REFERENCES`, `ON DELETE CASCADE|SET NULL|RESTRICT|NO ACTION`, `addForeignKey`, `->foreign()`, `references:`, `onDelete:`. If the migrations define FK constraints with explicit `ON DELETE` rules, the schema enforces integrity regardless of how data is modified (raw SQL, admin tools, bulk jobs) — that is the *stronger* guarantee.
  - **ORM-level second** — only *after* establishing what the DB enforces, look at ORM annotations: SQLAlchemy `ForeignKey(..., ondelete=...)`, Doctrine `@ORM\JoinColumn(onDelete=...)` / `#[ORM\JoinColumn(onDelete: ...)]`, Django `on_delete=`, Prisma `onDelete:`, GORM `constraint:OnDelete:`, Rails `foreign_key: { on_delete: }`. ORM cascades (`cascade={"remove"}`, `cascade_delete=True`) run only when deletion goes through the ORM — they are bypassed by raw SQL, bulk-deletes, and admin tooling.
  - **Do not flag missing ORM-level `onDelete` as a schema gap if the DB-level migration already enforces the constraint.** That is a false positive — the ORM annotation is then merely a hint for the ORM's own unit-of-work, not the integrity boundary. Report the DB-level enforcement as the finding.
  - **Do flag as a gap** when neither layer enforces the constraint (no `ON DELETE` in migrations *and* no `onDelete=` in ORM *and* only application-code cleanup) — that is the genuinely risky case.
- Check the other schema-quality dimensions:
  - Natural-key `UniqueConstraint` on tables where business rules require uniqueness (e.g., `(user_id, external_id)`).
  - Column types chosen deliberately: `SmallInteger` for bounded ranges, `BigInteger` for IDs that will grow, `DECIMAL` for money (not `FLOAT`), `TIMESTAMP WITH TIME ZONE` not naive.
  - Index strategy on hot paths. Partial indexes for nullable columns. Covering indexes for known aggregations.
- Count migrations; confirm each has a `downgrade()` that is non-trivial when the upgrade was destructive (e.g., enum conversion must reverse). Forward-only migration practice (no `down()`) is a deliberate trade-off, not automatically a downgrade to the grade — note it as a trade-off with rollback implications.

**Pushes grade up:**
- FK constraints enforced **at the DB level** via migrations, with explicit `ON DELETE` rules on every relationship. (Stronger than ORM-only.)
- Partial / covering indexes justified by query patterns.
- Migration downgrades exist and are non-trivial (or forward-only is deliberate with a documented rollback plan).

**Pushes grade down:**
- Bare integer columns referencing another table with **no** FK constraint at either the DB or ORM layer.
- `ON DELETE` rules absent **in both** migrations *and* ORM annotations, with cleanup delegated entirely to application code.
- No unique constraints where business rules require them.
- `FLOAT` for money. `TIMESTAMP` without TZ.
- Empty or TODO downgrades in a project that explicitly practices rollback.
- Missing indexes on obvious hot-path columns.

If the project has no database, mark `— N/A`.

---

## 9. Frontend quality

**Question:** Would a frontend-savvy reviewer flag anything about code style, type safety, or accessibility?

**Probes:**
- `tsconfig.json`: `strict`, `noUncheckedIndexedAccess`, `noImplicitReturns`, `exactOptionalPropertyTypes`. More enabled = stricter.
- Grep for `any` / `as any` / `@ts-ignore` / `@ts-expect-error`. Count density.
- Theme centralization: grep component files for hex color literals. If found, there is no theme module.
- Semantic HTML: grep for `<div onClick` (anti-pattern — should be `<button>`).
- Accessibility: `aria-label` on icon-only buttons? `alt` on `<img>`?
- Test IDs: `data-testid` pattern if the repo automates tests against the UI.
- Dead-export detection: `knip` / `ts-unused-exports` / `eslint-plugin-unused-imports` in CI.

**Pushes grade up:**
- Strict TS + `noUncheckedIndexedAccess` + near-zero `any`.
- Central theme tokens, no hex literals in components.
- CI blocks on dead exports.

**Pushes grade down:**
- Loose TS (`strict: false`).
- `@ts-ignore` shotgun.
- Hex colors in components with no theme module.
- Inaccessible markup.

If no frontend, mark `— N/A`.

---

## 10. Observability

**Question:** When the app is running in production at 3 AM, what can you see?

**Probes:**
- Logging format: plain `logging.info()` vs JSON formatter (`python-json-logger`, `pino`, `zap`, `zerolog`). JSON is required for aggregation.
- Request correlation: grep for `request_id` / `trace_id` / `correlation_id`. Present?
- Metrics endpoint: `/metrics`, Prometheus client, OTEL exporter.
- Slow-query logging: SQLAlchemy `before_cursor_execute` / `after_cursor_execute` hook, or ORM-level `before_query`.
- Sentry `before_send` with fingerprinting.
- Uptime monitor configured (often evidenced by a `/health` or `/healthz` endpoint).

**Pushes grade up:**
- JSON logs + correlation ID + Sentry + metrics endpoint.
- Slow-query guard (warn threshold).

**Pushes grade down:**
- Plain logs only, no correlation.
- No `/health` endpoint.
- Sentry sends every transient DB blip as a new issue.

---

## 11. Performance

**Question:** Are there obvious performance footguns?

**Probes:**
- N+1: grep for `for` over query results that then fire more queries. Look for `joinedload` / `selectinload` / `Include` / explicit `JOIN` — evidence of awareness.
- Async safety (Python): `asyncio.gather` on a single `AsyncSession` is unsafe. Blocking I/O (`requests`, `time.sleep`, file reads) in async handlers.
- Batching: bulk-insert vs per-row insert for import pipelines.
- Caching: Redis / in-memory / CDN evidence. Read-through or write-through?
- OOM mitigations: batch sizes explicitly tuned, swap configured, limits in Docker / k8s manifests.

**Pushes grade up:**
- Explicit join strategies on hot paths.
- Batch sizes with comments explaining why.
- No blocking I/O in async code.

**Pushes grade down:**
- Any `for` → per-item query pattern.
- `requests` or blocking sleep in async code.
- No batching on import pipelines that handle > 100 items.

---

## 12. Disaster recovery & backups

**Question:** If the production server's disk fails tomorrow, what data is lost?

**This is often the weakest dimension and is graded honestly.**

**Probes:**
- Search for `pg_dump`, `mysqldump`, `mongodump`, `redis-cli save`, `rsync` in any cron, systemd timer, GitHub Actions workflow, or bash script.
- Look for `deploy/`, `ops/`, `scripts/backup*`, `infra/backup*`.
- Check for managed-service use: RDS automated backups, Neon branching, Supabase PITR — these can tick the backup box without code in the repo, but should still be documented in README or deploy docs.
- Look for WAL archiving config in `postgresql.conf` or Docker compose env (`archive_mode = on`, `archive_command`).
- Look for a runbook / restore doc in `docs/` or README.
- Grep commits for "backup" and "restore" to see if the topic has ever been addressed.

**Pushes grade up:**
- Scheduled backup job with an offsite destination (S3, Hetzner Storage Box, B2, managed-service snapshot).
- PITR / WAL archiving enabled.
- Documented restore procedure.
- At least one recorded restore test (even a manual one in a commit message).

**Pushes grade down:**
- No evidence of any backup mechanism at all → grade cannot exceed C.
- Backups local-disk only (same machine as prod) → D.
- Backups exist but no restore documentation → B− at best.
- Backups + offsite + restore doc + tested restore → A.

For small side projects with no real users, this can still be B or C with a note ("pre-user deployment, not urgent"), but should never be silently graded A just because the rest of the system is nice.

---

## 13. Data privacy & GDPR/FADP

**Question:** If a user in the EU or Switzerland emails asking for their data deleted, can the operator comply?

**Probes:**
- Grep for `delete_account`, `deleteAccount`, `DELETE /users/me`, `DELETE /account`, `hard_delete`, `anonymize`.
- **Confirm the erasure path actually removes every user-owned row.** There are three valid designs and they must be evaluated differently — do not assume ORM-level cascade is the only "correct" answer:
  1. **DB-level `ON DELETE CASCADE`** defined in migrations — strongest, runs regardless of how the delete is issued.
  2. **ORM-level cascade** (`cascade={"remove"}`, `cascade_delete=True`, Django `on_delete=CASCADE`) — works only when deletion goes through the ORM; bypassed by raw SQL.
  3. **Application-code purge** (a `PurgeUserData` service that walks tables explicitly) — works if every user-FK table is covered; audit the service against the schema to verify no orphans.
  Any one of the three is acceptable for GDPR; flag a gap only when none of them covers a given user-FK table. Cross-reference with §8 findings — if §8 already established DB-level FKs exist with `ON DELETE CASCADE`, do not re-raise it here as a gap.
- **Also verify the erasure path is reachable** — a CASCADE in the schema that no endpoint/CLI/admin action calls is not GDPR-compliant. Trace from the `DELETE` endpoint (or CLI command) to confirm it actually triggers the cascade/purge.
- Data export: `GET /users/me/export`, `data_export.*`, right-to-data-portability.
- Consent: signup flow mentions terms/privacy?
- Privacy policy link on the site / in README?
- Third-party data (imported from APIs): is there a clear statement of what's stored, and is it purged on account deletion?
- `send_default_pii=False` on Sentry or equivalent.

**Pushes grade up:**
- Working `DELETE` endpoint (or self-service form) that reaches every user-owned table via DB cascade, ORM cascade, or an audited purge service — all three are acceptable.
- Data-export endpoint.
- Privacy policy link.
- No PII in logs / Sentry.

**Pushes grade down:**
- No account-deletion endpoint at all (even if schema would cascade).
- User-owned tables that no cascade mechanism (DB, ORM, or application code) covers — orphans guaranteed on deletion.
- Third-party imported data with no explicit purge logic.
- PII leaking into logs / Sentry.

If the app stores no PII at all (public data, no accounts), mark `— N/A: no user accounts or PII stored` and say why.

---

## 14. Dependency management & supply chain

**Question:** Are third-party deps kept patched, and is the supply chain hardened against bad packages?

**Probes:**
- **Automation:**
  - `.github/dependabot.yml` — present, schedule (weekly/daily), which ecosystems.
  - `renovate.json` or Renovate config.
  - Any scheduled workflow that runs `npm outdated` / `uv pip list --outdated`.
- **Lockfiles:**
  - `uv.lock`, `poetry.lock`, `requirements.txt` (with pinned versions), `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`, `go.sum`, `Gemfile.lock`, `composer.lock`.
  - Confirm they're tracked (`git ls-files | grep lock`).
  - Check CI for `npm ci` / `pnpm install --frozen-lockfile` / `uv sync --locked` / `cargo build --locked` / `bundle install --deployment`.
- **Audit:**
  - `npm audit`, `pip-audit`, `cargo audit`, `govulncheck`, `bundler-audit` in CI.
- **Base images:**
  - Dockerfile `FROM` lines — pinned to a major.minor tag (`python:3.13-slim`) at minimum, ideally `@sha256:` digest.
- **SBOM / signing:**
  - If the project is security-conscious, look for `syft`, `cosign`, SLSA provenance.

**Pushes grade up:**
- Dependabot weekly across all ecosystems.
- Lockfiles committed and verified in CI.
- Audit step in CI that fails on high-severity vulns.
- Pinned base images.

**Pushes grade down:**
- No Dependabot/Renovate and no other update automation → cannot exceed B−.
- Lockfiles missing or not verified → cannot exceed B.
- No audit step → cannot exceed B.
- `FROM ubuntu:latest` or similar floating tags → cannot exceed B.

---

## 15. Frontend bundle & performance

**Question:** How heavy is the payload to a mobile user on 4G?

**Probes:**
- Build the frontend if possible (`npm run build`, `vite build`) or check the `dist/` size of an existing build if present in the repo or in deployed artifacts.
- Look at the main/index chunk size, both raw and gzipped.
- Grep for `React.lazy`, `lazy(`, `import(`, `loadable`, `dynamic` (Next.js) — evidence of code splitting.
- Check heavy dependencies: chart libs (recharts, chart.js, d3), board/game libs (three.js, react-chessboard), rich-text editors (TinyMCE, Quill), video players. Are they loaded only when needed, or in the initial bundle?
- `sideEffects` in `package.json`: `false` or explicit list enables tree-shaking.
- Check `index.html` for preconnect, preload, font display swap.
- Source maps: are they committed to production builds? Exposed at a public URL?

**Pushes grade up:**
- Main chunk < 250 KB gzipped.
- Route-level code splitting.
- Heavy libs lazy-loaded.
- `sideEffects: false` or precise list.

**Pushes grade down:**
- Main chunk > 1 MB gzipped.
- No code splitting, everything in one bundle.
- Heavy libs imported from entry point for features only used on a specific page.

If no frontend: `— N/A`.

---

## 16. CI/CD execution speed

**Question:** How long does "push to PR → merged to main" take, and what gates the pipeline?

**Probes:**
- If GitHub Actions: run `gh run list --workflow=<main-ci>.yml --limit 5 --json databaseId,conclusion,createdAt,updatedAt` and compute median duration. Check both PR-gate and main-branch runs.
- Read `.github/workflows/*.yml` (or GitLab/Circle/Azure config) for:
  - Jobs and their ordering (parallel vs sequential).
  - Use of `actions/cache` or native ecosystem cache (`actions/setup-python` with `cache: 'pip'`).
  - Test parallelization flags: `pytest-xdist`, `vitest --shard`, `jest --maxWorkers`, `go test -parallel N`, `rspec --tag`.
  - Matrix / sharding.
  - Service containers for real DB testing (adds time but pays for itself).
- Deploy step: manual `workflow_dispatch` / on push / on tag / separate workflow.

**Pushes grade up:**
- Median main-branch run < 5 minutes for a mid-size project.
- Test parallelization in place.
- Dependency caching in place.
- Parallel jobs where independent.

**Pushes grade down:**
- Median > 15 minutes for a project of any size.
- Sequential jobs that could be parallel.
- No caching — `npm install` from scratch each time.
- Long tests without sharding.

**How to report timing when you can't measure directly:** say so. "Could not run `gh run list` in this environment; workflow structure suggests roughly N minutes based on steps." Being explicit about the limitation is better than inventing a number.
