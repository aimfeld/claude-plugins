# Dimensions Reference

For each of the 17 dimensions, this file lists: what to look for, which probes to run, common evidence patterns, and what pushes the grade up or down.

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

**Canonical probes (run verbatim — different greps give different counts, which makes re-audits look like the code changed when it didn't):**

- Python bare excepts (files): `rg -l '^\s*except\s*:\s*(#.*)?$' -t py --glob '!tests/**' --glob '!test/**' --glob '!__tests__/**' --glob '!fixtures/**' --glob '!reports/**' | wc -l`
- Python bare excepts (total sites): `rg -c '^\s*except\s*:\s*(#.*)?$' -t py --glob '!tests/**' --glob '!test/**' --glob '!__tests__/**' --glob '!fixtures/**' --glob '!reports/**' | awk -F: '{s+=$NF} END {print s+0}'`
- JS/TS empty catches (files): `rg -l 'catch\s*\([^)]*\)\s*\{\s*\}' -t ts -t tsx -t js -t jsx --glob '!node_modules/**' --glob '!tests/**' --glob '!__tests__/**' --glob '!reports/**' | wc -l`
- Go error-dropping `_ =` (rough): `rg -c '_\s*=\s*[a-zA-Z_][a-zA-Z0-9_.]*\(' -t go --glob '!vendor/**' --glob '!*_test.go' | awk -F: '{s+=$NF} END {print s+0}'` — this is a *signal* for dropped error returns, read a sample to confirm.

Report the exact numbers these commands produce; if you diverge from them (e.g., to include tests or use a different pattern), say so and say why.

**Probes:**
- Run the canonical probes above. Report counts.
- Grep for `capture_exception`, `Sentry.captureException`, `logger.error`, `panic`, `rescue`. Count sites. Divide by total LOC for a rough density.
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

### Quarantine rule (non-negotiable)

Any path listed in `CREDENTIAL_FILES_HIGH_CONFIDENCE` or `CREDENTIAL_FILES_REVIEW` in the stats output is **read-forbidden** for the remainder of this audit. Do not call `Read`, `cat`, `head`, `tail`, or any tool that emits file contents on those paths. The bash-produced classification label is the only signal you use. The report cites the path, never the body. The purpose is simple: secret bytes must not enter the LLM context — once they're in context they can be logged, cached, or echoed back, and that risk is unacceptable for passwords, private keys, and env-var values.

When running the content greps in Probe 1 below, **exclude every entry in `CREDENTIAL_FILES_HIGH_CONFIDENCE` and `CREDENTIAL_FILES_REVIEW`** via `:(exclude)<path>` pathspecs (for `git grep`) or `--exclude=<path>` (for `grep`/`rg`). Without these exclusions, a committed `.env` or credential JSON would match `API_KEY=` / `-----BEGIN` / `"client_secret"` and leak the *value* through the grep output. The quarantine is what prevents that.

**Probes:**

- **Probe 0 — consult `CREDENTIAL_FILES_HIGH_CONFIDENCE` and `CREDENTIAL_FILES_REVIEW` from the stats output.** The bash script has already classified each file using silent content-free probes (`grep -q` on PEM headers and JSON key names). Treat the labels as authoritative:
  - **HIGH_CONFIDENCE hits.** Real secret by default — the filename/directory convention is canonical. No content inspection needed, ever. Flag as Critical. Labels you'll see: `real-oauth-client-secret`, `real-gcp-service-account`, `ssh-private-key`, `kubeconfig`, `env-file`, `credential-dir-file`, `credential-file`.
  - **REVIEW hits** with `real-*` label (`real-private-key`, `real-private-key-encrypted`, `real-gcp-service-account`, `real-oauth-client-secret`, `real-aws-credentials`, `real-htpasswd`) → real secret. Flag as Critical.
  - **REVIEW hits** with `binary-keystore-not-inspected` label → treat as real secret by default (a committed `.pfx`/`.p12`/`.jks` outside a fixture path is almost always a real keystore).
  - **REVIEW hits** with `public-cert-ignore` / `public-key-ignore` / `csr-public-ignore` → public material, not a grade-floor trigger. Mention only if the public material shouldn't be in the source tree (e.g., a production CA bundle that should ship in the container image).
  - **REVIEW hits** with `unclassified` label → cite the path, flag for human review, **do not read the file**, do not grade-floor. The label means the bash probe couldn't identify the shape; a human should open it in a scratch buffer outside the audit.
  - **Report format per hit:** cite the path. If the path itself contains a token-shaped component (e.g., `client_secret_<TOKEN>.json`), redact the token component as `<REDACTED-TOKEN>` in §4 prose; the full path stays in the §5 Evidence column so the maintainer can locate the file.

- **Probe 1 — `git grep` for common secret patterns** in source code (credential files are already handled by Probe 0, and **must be excluded from this grep** per the Quarantine rule): `API_KEY`, `SECRET_KEY`, `PASSWORD`, `TOKEN`, `AWS_`, `sk-`, `xoxb-`, `ghp_`, `-----BEGIN`, `postgres://`, `mysql://`. **Also exclude `reports/`, `.planning/`, `docs/`, `.claude/`, and `.idea/`** — prior reports will contain literal pattern strings that self-match on re-runs. Use `--exclude-dir=reports --exclude-dir=.planning --exclude-dir=docs --exclude-dir=.claude --exclude-dir=.idea` plus a `:(exclude)<path>` pathspec for every `CREDENTIAL_FILES_*` entry (or the `grep`/`rg` equivalent).
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

**Grade floor (supersedes all positive signals in this dimension):**
- **Any** `CREDENTIAL_FILES_HIGH_CONFIDENCE` hit, or any `CREDENTIAL_FILES_REVIEW` hit whose bash-emitted label starts with `real-` or is `binary-keystore-not-inspected` → Secrets dimension **cannot exceed D** until the file is rotated (treat it as compromised), the git history is filtered (`git filter-repo` or equivalent), and the path is added to `.gitignore`. This is a hard floor: even if every other probe in this dimension looks clean, a tracked credential file holds the grade at D. Cite the floor explicitly in the §4.4 finding.
- Labels `public-cert-ignore`, `public-key-ignore`, `csr-public-ignore`, and `unclassified` are **not** grade-floor triggers.

If you find anything that could be a real secret, redact it in the report (`<REDACTED: pattern match>`) and flag it as immediate-action.

---

## 5. Code smells

**Question:** Is the codebase living in the present, or are there ghost rooms?

**Canonical probes (run verbatim):**

- TODO / FIXME / XXX / HACK / DEPRECATED (total sites): `rg -c '\b(TODO|FIXME|XXX|HACK|DEPRECATED)\b' --glob '!node_modules/**' --glob '!vendor/**' --glob '!.venv/**' --glob '!dist/**' --glob '!build/**' --glob '!reports/**' --glob '!CHANGELOG.md' --glob '!CLAUDE.md' | awk -F: '{s+=$NF} END {print s+0}'`
- Same marker, file count: replace `-c` with `-l` and `awk` with `wc -l`.

Report the exact numbers. Spot-check a handful (the oldest-looking, the scariest-sounding) — the count is the metric, the spot-check is the evidence.

**Probes:**
- Run the canonical probe above.
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
- **IDE-committed static analysis profiles:** look for `.idea/inspectionProfiles/*.xml`, `.vscode/settings.json`, `.vscode/extensions.json`, `.editorconfig` (cross-reference `references/languages.md` for per-language signals). When present, read the profile and list which inspections are `enabled="true"` and which external tools they wire up (PHPStan, Psalm, PHP-CS, PHPMD, ESLint, mypy, ruff, rubocop, SpotBugs, etc.). For every external tool named by the profile, cross-reference against: (a) whether its config file exists at the project root (`phpstan.neon`, `psalm.xml`, `.eslintrc*`, `mypy.ini`, `.rubocop.yml`), (b) whether CI also runs it. Report each tool in one of three states:
  - **CI-enforced** — tool runs on PR, blocks merge. Strongest.
  - **IDE-enforced** — tool runs in the editor only. Weaker: depends on every contributor using that specific IDE, doesn't gate merges or outside contributions, runs manually rather than automatically.
  - **Configured but dead** — tool config file exists on disk but neither CI nor the IDE profile activates it (e.g. `phpstan.neon.dist` committed, but `PhpStanGlobal enabled="false"` in the JetBrains profile and no CI step runs `vendor/bin/phpstan`). This is the most misleading state — the repo *looks* covered but nothing enforces the rules.
- Migration discipline (if DB): count migrations, spot-check that `downgrade()` is non-trivial and destructive transitions carry explicit casts.

**Pushes grade up:**
- Test LOC ≥ 50% of code LOC for service-oriented projects.
- Integration tests run against real DB (or a container) in CI.
- Multi-gate CI (lint + type check + dead-export + tests).
- Migrations have working downgrades.
- Committed IDE inspection profile that actively enforces multiple classes of rules (style + security-advisory + debug-leak + dead-code), *in addition to* CI gates.

**Pushes grade down:**
- Test LOC < 10% of code LOC for production systems.
- Only mocks, no integration path.
- No type checker in CI for a project in a type-checkable language.
- Migrations without downgrade or with empty downgrade.
- Tool config file present (`phpstan.neon`, `psalm.xml`, `.eslintrc`, `mypy.ini`, `.rubocop.yml`) but no enforcement path — neither CI nor the committed IDE profile activates it. Worse than not having the config, because it gives a false signal of coverage.
- IDE inspection profile is the *only* quality gate (no CI), especially on codebases with external contributors or multi-editor teams. IDE-only enforcement doesn't scale past the team that sits in that specific IDE, and runs manually rather than gating merges. Credit the dev-time enforcement, but still flag the CI gap.

---

## 7. Security

**Question:** Would a reviewer with a security hat on flag anything?

**Canonical probes (run verbatim — the SQL-injection count specifically drifted between prior audits):**

- Python raw-SQL interpolation (f-strings into execute): `rg -n 'execute\s*\(\s*f["\x27]' -t py --glob '!tests/**' --glob '!test/**' --glob '!reports/**'`
- Python raw-SQL concatenation into execute/query: `rg -n 'execute\s*\([^)]*\+|query\s*\([^)]*\+' -t py --glob '!tests/**' --glob '!test/**' --glob '!reports/**'`
- JS/TS string-concat into query (Postgres/mysql drivers): `rg -n 'query\s*\(\s*[`\x27"][^`\x27"]*\$\{' -t ts -t tsx -t js --glob '!node_modules/**' --glob '!tests/**'`
- CORS wildcard: `rg -n 'allow_origins\s*=\s*\[\s*["\x27]\*["\x27]|Access-Control-Allow-Origin["\x27:]\s*\*' --glob '!node_modules/**' --glob '!reports/**'`
- Sentry PII flag (grep for `send_default_pii=True`): `rg -n 'send_default_pii\s*=\s*True' -t py --glob '!reports/**'`

Report every hit line. Every raw-SQL hit is a §6 Substantial Problem candidate regardless of overall grade.

**Probes:**
- Auth dependencies: find the auth middleware / dependency. Grep for routes that should require auth but don't declare the dependency.
- SQL: run the canonical probes above. Any finding is immediate-action.
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

**Canonical probes (run verbatim):**

- Sentry capture sites: `rg -c 'capture_exception|Sentry\.captureException|sentry_sdk\.capture_' --glob '!node_modules/**' --glob '!reports/**' | awk -F: '{s+=$NF} END {print s+0}'`
- Apps with Sentry init (monorepo heuristic): `rg -l 'sentry_sdk\.init\(|Sentry\.init\(' --glob '!node_modules/**' --glob '!reports/**' | wc -l`
- Correlation-ID plumbing: `rg -c '(request_id|trace_id|correlation_id|X-Request-Id)' --glob '!node_modules/**' --glob '!reports/**' | awk -F: '{s+=$NF} END {print s+0}'`
- JSON logger presence: `rg -l 'python-json-logger|pino|zap|zerolog|JsonFormatter' --glob '!node_modules/**' --glob '!reports/**'`

Report both absolute counts and (where meaningful) coverage ratios — e.g., "Sentry init in 13 of 42 apps = 31%".

**Probes:**
- Run the canonical probes above.
- Logging format: plain `logging.info()` vs JSON formatter (`python-json-logger`, `pino`, `zap`, `zerolog`). JSON is required for aggregation.
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

**Canonical probes (run verbatim):**

- Python over-pinned apps in a monorepo (common footgun — each app re-pinning transitive deps decouples it from any central upgrade strategy). Flags sub-projects with >15 exact pins in `requirements.txt`, `requirements-*.txt`, or `[project] dependencies` arrays:
  ```
  find . -path '*/node_modules' -prune -o -path '*/.venv' -prune -o -path '*/vendor' -prune -o \
    \( -name 'requirements*.txt' -o -name 'constraints*.txt' \) -print 2>/dev/null \
    | while IFS= read -r f; do
        c=$(grep -cE '^[A-Za-z0-9_.-]+[[:space:]]*==' "$f" 2>/dev/null); c=${c:-0}
        [ "${c}" -gt 15 ] 2>/dev/null && printf '  %s: %d pinned\n' "$f" "$c"
      done
  ```
  Equivalent for Node (`package.json` with >15 exact-version `^`-less / `~`-less deps), Ruby (`Gemfile` lines with `'= x.y.z'`), Go (`go.mod` exact version count isn't a red flag — Go's semver is different). For monorepos, finding 2+ such apps is a §6 Substantial Problem candidate.
- Dockerfile base-image pinning: `rg -n '^FROM\s+' -g '**/Dockerfile*' --glob '!reports/**'` and note which lines use `@sha256:` (pinned) vs plain tag (floating).

Report the exact list of over-pinned apps with their pin counts, not just "several apps are over-pinned."

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

---

## 17. Technical debt & legacy stack

**Question:** Is the tech stack still alive — language runtimes on supported versions, frameworks within reach of latest, load-bearing dependencies still maintained upstream — or is the team accumulating a migration backlog they haven't acknowledged?

This dimension is orthogonal to §14. §14 asks whether the *update process* is wired up (Dependabot, lockfiles, CVE scans). §17 asks what version you are *actually on right now*, and whether the upstream projects you depend on are still alive. A project can have excellent Dependabot automation and still be on Python 3.7 with a pile of archived npm packages. Grade them independently.

**Probes:**
- **Primary language runtime version** vs the language's current support window:
  - Python: `requires-python` in `pyproject.toml`, `python_requires` in `setup.py`, `.python-version`, `runtime.txt`. Compare to the CPython support matrix (`3.9` is the current floor as of writing; anything older is EOL).
  - Node: `engines.node` in `package.json`, `.nvmrc`, `.node-version`, CI setup-node version. Compare to the active LTS line (Node 20 / 22 are active; 18 and below are EOL or entering EOL).
  - Go: `go` directive in `go.mod`. Go supports the last two minors only.
  - Ruby: `.ruby-version`, `Gemfile`'s `ruby` directive.
  - Java / Kotlin: JDK version in `build.gradle` / `pom.xml`. Compare to current LTS (21, 17).
  - .NET: `TargetFramework` in `*.csproj`. Compare to .NET current LTS.
  - PHP: `require.php` in `composer.json`. Compare to supported PHP branches.
  - Rust: `rust-toolchain` / `rust-toolchain.toml`. Rust's MSRV policy is looser — "at least six months old" is fine.
- **Framework major versions** vs latest major release. Cross-reference `package.json`, `pyproject.toml`, `Gemfile`, `composer.json`, `pom.xml`, etc. against the current major — React (19), Next.js (15), Angular, Vue (3), Django (5), FastAPI, Flask (3), Spring Boot (3), Rails (7/8), Laravel (11), Symfony (7), Express (5), .NET (9). Two-plus majors behind is a finding.
- **Datastore / infra majors** from Docker / compose / README: PostgreSQL, MySQL, Redis, Elasticsearch / OpenSearch. Check against upstream supported-versions pages.
- **Legacy-technology exposure.** Anything load-bearing in a technology the rest of the industry has moved off: AngularJS 1.x, CoffeeScript, Backbone, Ember pre-3, jQuery in a modern SPA codebase, moment.js, class components in an otherwise-hooks React codebase, Python 2 compat shims, Flow types alongside (or instead of) TypeScript.
- **Dependency maintenance status** — is every direct dependency's upstream still alive? For 30+ direct deps, per-dep lookups aren't tractable — lean on **bulk ecosystem signals** instead of maintaining a curated list:
  - **Registry deprecation warnings** — one command per ecosystem, authoritative. Node: `npm outdated` + `npm ls` surface packages the maintainer flagged deprecated. Python: `pip-audit` + `pip list --outdated`. Rust: `cargo outdated`. Go: `go list -m -u all`. Ruby: `bundle outdated`. PHP: `composer outdated --direct`.
  - **Last-release age.** The same `outdated` commands plus `npm view <pkg> time` / `pip index versions <pkg>` give last-publish dates. Flag any direct dep with no release in > 18 months.
  - **PyPI `Development Status` classifier.** Machine-readable from package metadata; `Development Status :: 7 - Inactive` is an explicit abandonment signal.
  - **GitHub `archived: true`.** Authoritative per-repo flag. For suspicious deps surfaced by the steps above, `gh api repos/{owner}/{repo} --jq .archived` settles it in one call.
  - **Lockfile staleness.** If the lockfile churns frequently but a specific dep's resolved version hasn't moved in 3+ years (`git log -p -- package-lock.json | grep <pkg>`), the upstream has likely stalled.
  - **Known-orphan examples, for calibration only** (not a checklist — verify with the signals above): `request` → `undici`; `moment` → `date-fns` / `Temporal`; `node-sass` → `sass`; `tslint` → `eslint`; `enzyme` → `@testing-library/react`; `bower`, `gulp` in many SPA contexts.

  Flag each unmaintained load-bearing dep individually with last-release date and canonical successor where one exists. Security-sensitive unmaintained deps (HTTP clients, crypto, auth) are heavier findings than benign ones (a logging helper).
- **Deprecated APIs in active use.** `componentWillMount` / `componentWillReceiveProps`, legacy React context, `PropTypes` on new components, Python 2 compat imports, `asyncio.get_event_loop()` in 3.12+ code, Django `url()` instead of `path()`, Rails `before_filter`, etc.
- **Build tooling currency.** webpack 4 vs 5 / Vite / Turbopack; Babel 6 vs 7; setuptools-only vs uv / poetry / hatch; plain `npm` vs `pnpm` / `yarn` for large monorepos; Make vs Bazel / Nx where complexity demands it.
- **Blocked-upgrade signals.** Grep the repo for comments like `# do not bump`, `// locked to 4.x`, `# can't upgrade because`, TODOs referencing a stuck dep, issues labeled `upgrade-blocker`. These are the debt the team already knows about.

**Pushes grade up:**
- All runtimes on active LTS / actively supported versions.
- Frameworks within one major of latest, or on the latest LTS for frameworks that ship LTS lines.
- No load-bearing legacy technology.
- Every direct dependency released within the last ~12 months (or has a clear long-term-stable signal, e.g., `lodash` — mature, stable, still maintained).
- Documented upgrade intent in CHANGELOG / README / issues — even as TODOs — showing the team tracks major versions.

**Pushes grade down:**
- Language runtime EOL or entering EOL in < 12 months (Python < 3.9, Node ≤ 18 post-EOL, PHP < 8.2, Go more than two minors behind, .NET on a non-LTS past its support window).
- A major framework two or more majors behind (React 16 with 19 out, Angular 1.x, Django 3.x with 5 out, Rails 5.x, Laravel 7).
- Load-bearing legacy technology with no migration plan (AngularJS, CoffeeScript, Flash, Silverlight).
- Direct dependencies whose upstream is archived / unmaintained / last-released > 18 months ago, with no migration plan — especially security-sensitive ones.
- Pinned-forever dependencies with `# do not bump` and no replacement plan.
- Deprecated APIs mixed into *new* code (old patterns added in the last 90 days).

**Calibration:**
- **A** — everything current, no legacy corners, every direct dep actively maintained.
- **A−** — one acknowledged outlier with a migration plan (e.g., "one AngularJS admin page, ticket #234 to rewrite in React").
- **B** — a couple of majors behind on a framework or two, all runtimes still supported, no archived deps.
- **C** — runtime approaching EOL, or one archived security-sensitive dep still in use, or a load-bearing legacy area with no plan.
- **D** — runtime already EOL, or multiple archived deps, or AngularJS 1.x still load-bearing with no migration.
- **F** — stack is effectively unmaintainable; a new hire would need to learn an obsolete language or framework to contribute.

If the project is brand-new (initial commit < 6 months ago) and everything is current, grade A on the state *now* but note that §17 will need re-evaluation annually — this dimension drifts on its own.
