# codebase-audit

[![stats script CI](https://github.com/aimfeld/claude-plugins/actions/workflows/codebase-audit-script.yml/badge.svg?branch=main)](https://github.com/aimfeld/claude-plugins/actions/workflows/codebase-audit-script.yml)

A [Claude Code](https://www.claude.com/product/claude-code) plugin that produces a thorough, evidence-based software quality assessment for any git repository — architecture, security, database design, observability, testing, disaster recovery, GDPR, dependency management, frontend bundle performance, and CI/CD speed.

Every grade and finding is backed by a concrete `file:line` pointer so a reviewer can verify any claim in under a minute.

## What you get

A single Markdown report (~3–6 pages) written to `reports/{project}_quality_assessment_{YYYY-MM-DD}.md`:

- **Method & Limitations block** — states what the report is and is not, defines confidence levels (Verified / Likely / Inferred), and reprints the grade rubric inline
- **Summary stats** — LOC, test LOC, test/code ratio, test-suite run (optional), coverage, commits in last 90 days, active contributors, primary languages
- **Executive summary** — graded table across 17 dimensions, with a 3–4 sentence bottom line
- **Operational picture** — numbered data-flow walkthrough (how the system actually runs)
- **Per-dimension findings** — each with `file:line` evidence
- **Findings Register** — consolidated table: ID × Dimension × Finding × Severity × Confidence × Evidence × Effort
- **Substantial problems** — numbered, with effort estimates
- **What's notably good** — patterns worth keeping
- **Recommended actions** — Immediate / Short term / Medium term

## Example report

A full sample assessment of a production open-source codebase lives at [`examples/flawchess_quality_assessment_2026-04-18.md`](./examples/flawchess_quality_assessment_2026-04-18.md). A taste:

### Summary stats (excerpt)

| Metric | Value | Notes |
|---|---|---|
| Total code LOC | 39,531 (Python 25,509 + TSX 11,140 + TS 2,882) | `tokei` exact counts |
| Test LOC | 19,034 across 39 files | Test/code ratio ≈ 48% |
| Test suite run — backend | `810 passed / 810, coverage 89%` | `uv run pytest --cov=app` in 16.21s against a real Postgres 18 container |
| Test suite run — frontend | `77 passed / 77, coverage 87%` (covered files only) | `vitest run --coverage` — measures the ~100 LOC of utilities imported by 6 test files, not the full `src/` tree |
| Commits (last 90 days) | 776 | Extremely active (~8.6/day) |
| Active contributors (last 90 days) | 2 (same person, two emails) | Effectively single-maintainer |

### Executive summary

| Dimension | Grade | One-line finding |
|---|---|---|
| Architecture | **A−** | Clean router → service → repository layering; zero SQL in routers; two outlier god-files (`endgame_service.py` 1,701 LOC, `endgame_repository.py` 775 LOC) justified by domain but ripe for split. |
| Code duplication | **A** | `query_utils.apply_game_filters()` is the single source for game filtering across all repositories (`query_utils.py:13`). |
| Error handling / Observability | **A−** | 10+ `sentry_sdk.capture_exception` sites with thoughtful cause-chain fingerprinting (`main.py:23-39`); plain-text `logging.getLogger(__name__)` across 5 services, no structured JSON. |
| Secrets / config | **A−** | `.env` and `prod.env` are `.gitignored` and never committed; defaults explicit; stale comment at `config.py:14` claims "development bypasses JWT auth" but no such bypass exists in the code — misleading. |
| Code smells | **A** | Zero TODO/FIXME/HACK markers; magic numbers extracted into named constants (`DEFAULT_ELO_THRESHOLD`, `_BATCH_SIZE`); no commented-out blocks. |
| Maintainability / tests | **B+** | Backend excellent (810 tests, 89% cov, real-DB pytest-asyncio); frontend has only 6 utility tests, zero component/page tests; CI runs ruff + ty + pytest + eslint + vitest + knip — strong gating. |
| Security | **A−** | JWT + OAuth with CSRF double-submit (`auth.py:85-96`, "CVE-2025-68481 fix" comment), timing-safe CSRF comparison, IP rate-limiter on guest creation, ORM-only queries (zero `text(`), Pydantic validation at every router boundary. Sole finding: stale/misleading comment at `config.py:14`. |
| Database design | **A** | All FKs use `ondelete="CASCADE"` (5/5), named `UniqueConstraint`s on natural keys, compound indexes on `(user_id, full_hash)` etc., 39 Alembic migrations with `downgrade()` coverage. |
| Frontend quality | **A−** | Strict TS (`noUncheckedIndexedAccess` on), zero `@ts-ignore`/`as any`, centralized `theme.ts`, 319 `data-testid` + 64 `aria-label` occurrences, knip in CI. Gap: zero component/page unit tests. |
| Observability | **B** | Sentry backend + frontend + `before_send` fingerprint; `pg_stat_statements` loaded (`docker-compose.yml:12`); Umami web analytics self-hosted. No structured-JSON logging, no request-ID correlation header, no metrics endpoint. |
| Performance | **A−** | Async-correct throughout (no `asyncio.gather` on shared sessions, no blocking `requests`/`time.sleep`), `_BATCH_SIZE=28` on imports after OOM incident (`import_service.py:37`), chunked `INSERT`s respect PG param limit (`game_repository.py:88-91`). Single main bundle (286 KB gz) is borderline — no code splitting. |
| Disaster recovery / backups | **B** | Hetzner daily whole-server snapshot, 7-day rolling retention. No PITR (no WAL archiving), no separate logical `pg_dump` for longer horizons, no tested restore on record. |
| Data privacy / GDPR | **B−** | Privacy policy page, consent-via-signup, Sentry `send_default_pii=False` (`main.py:54`), cascade delete wired through schema. Deletion is email-request-only (`Privacy.tsx:57-70`) — no self-service `DELETE /users/me` endpoint, no data-export endpoint. |
| Dependency management | **C+** | Lockfiles committed and verified in CI; no Dependabot / Renovate configured; no `pip-audit`/`npm audit` in CI; Dockerfile base image `python:3.13-slim` floating (not pinned to digest). |
| Frontend bundle / perf | **B** | Main bundle 980 KB raw / 286 KB gz (single chunk, no `React.lazy`), PWA + Workbox configured sanely, prerender plugin for SEO, VitePWA polling every 60 min to avoid stale JS. Should code-split the endgame-charts route from the opening-explorer route. |
| CI/CD execution speed | **A−** | ~2m25s median across last 5 runs. ruff → ty → pytest → eslint → tsc/vite → vitest → knip in sequence, single job, `uv sync --locked`. Deploy gated behind manual `workflow_dispatch` with health-check loop. |
| Technical debt / legacy stack | **A** | Python 3.13, Node 24, React 19, FastAPI 0.115, Vite 7, PostgreSQL 18, SQLAlchemy 2.x async — all current majors. Zero deprecated APIs; no archived direct deps. `ty` (preview-stage type checker) is the only novel-tech bet. |

> **Bottom line.** Production-grade for a single-maintainer project. The central architectural bet (Zobrist-hash position matching via compound indexes) is load-bearing and sound, the backend discipline is near-exemplary (strict typing via `ty`, clean layering, 89% test coverage, real-DB integration tests), and the deploy path is boringly reliable. The genuine gaps are narrow and well-known: no automated dependency updates, no self-service account deletion, no frontend component tests, and a single 980 KB main JS bundle. Remaining work is polish — closing four small, cheap gaps — not rescue.

[Read the full report →](./examples/flawchess_quality_assessment_2026-04-18.md)

## Dimensions graded

1. Architecture & layering
2. Code duplication
3. Error handling & observability
4. Secrets & configuration
5. Code smells
6. Maintainability & tests
7. Security
8. Database design
9. Frontend quality
10. Observability
11. Performance
12. Disaster recovery & backups
13. Data privacy & GDPR/FADP
14. Dependency management & supply chain
15. Frontend bundle & performance
16. CI/CD execution speed
17. Technical debt & legacy stack

Grades on a standard A–F scale with `+`/`−` half-steps. Dimensions without enough evidence are marked `—` rather than guessed.

## Install

```
/plugin marketplace add aimfeld/claude-plugins
/plugin install codebase-audit@aimfeld
```

## Updating

Third-party marketplaces have auto-update **disabled by default** in Claude Code — only the official Anthropic marketplace auto-updates out of the box. To receive new versions of this plugin automatically, turn auto-update on once:

1. Run `/plugin`
2. Go to the **Marketplaces** tab
3. Select `aimfeld`
4. Choose **Enable auto-update**

After that, Claude Code will refresh the marketplace at startup and update the plugin. When a plugin changes, you'll be prompted to run `/reload-plugins` to activate the new version.

To update on demand (works whether or not auto-update is on):

```
/plugin marketplace update aimfeld
/reload-plugins
```

Requires Claude Code ≥ 2.0.70 for native marketplace auto-update. See [CHANGELOG.md](./CHANGELOG.md) for what's in each release.

## Use

This skill is model-invoked — just ask naturally:

- "Audit this repo"
- "Give me a quality assessment"
- "Is this codebase production ready?"
- "What are the weak spots in this project?"

Or invoke it directly:

```
/codebase-audit:report
```

Claude will:

1. Orient on the project (README, manifests, deploy shape)
2. Run the stats collector (LOC, coverage artifacts, git activity, CI timing)
3. Survey operational context (entrypoints, migrations, config, deploy)
4. Probe each of the 17 dimensions with targeted greps and reads
5. Write the graded report to `reports/`

Typical run: 5–15 minutes on a medium-sized repo.

## Requirements

- [Claude Code](https://www.claude.com/product/claude-code)
- Bash (the stats collector is a shell script)
- Optional but recommended: `tokei` for accurate LOC breakdown. The stats collector offers to install it if missing.

Works on any language — Python, TypeScript/JavaScript, Go, Rust, Java, Ruby, PHP, C#, etc.

## License

MIT — see [LICENSE](../../LICENSE).
