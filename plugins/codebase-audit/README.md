# codebase-audit

A [Claude Code](https://www.claude.com/product/claude-code) plugin that produces a thorough, evidence-based software quality assessment for any git repository — architecture, security, database design, observability, testing, disaster recovery, GDPR, dependency management, frontend bundle performance, and CI/CD speed.

Every grade and finding is backed by a concrete `file:line` pointer so a reviewer can verify any claim in under a minute.

## What you get

A single Markdown report (~3–6 pages) written to `reports/{project}_quality_assessment_{YYYY-MM-DD}.md`:

- **Summary stats** — LOC, test LOC, test/code ratio, coverage, commits in last 90 days, active contributors, primary languages
- **Executive summary** — graded table across 17 dimensions, with a 3–4 sentence bottom line
- **Operational picture** — numbered data-flow walkthrough (how the system actually runs)
- **Per-dimension findings** — each with `file:line` evidence
- **Substantial problems** — numbered, with effort estimates
- **What's notably good** — patterns worth keeping
- **Recommended actions** — Immediate / Short term / Medium term

## Example report

A full sample assessment of a production open-source codebase lives at [`examples/flawchess_quality_assessment_2026-04-17.md`](./examples/flawchess_quality_assessment_2026-04-17.md). A taste:

### Summary stats (excerpt)

| Metric | Value | Notes |
|---|---|---|
| Total code LOC | 39,531 (Python 25,509 + TSX 11,140 + TS 2,882) | `tokei` exact counts |
| Test LOC | 19,034 across 39 files | Test/code ratio ≈ 48% |
| Test coverage | Not measured | `htmlcov/` present but not parsed |
| Commits (last 90 days) | 775 | Extremely active (~8.6/day) |
| Active contributors (last 90 days) | 2 (same person, two emails) | Effectively single-maintainer |

### Executive summary

| Dimension | Grade | One-line finding |
|---|---|---|
| Architecture | **A−** | Clean router → service → repository layering across 7,102 LOC of services/repos; one outlier: `endgame_service.py:1701` is a 1,701-LOC god-file bundling classification, aggregation, and formatting. |
| Code duplication | **A** | Single `apply_game_filters()` (`app/repositories/query_utils.py:13`) consumed by 6 repositories; 0 asyncio.gather-on-session violations across `app/`. |
| Error handling / Observability | **A−** | 13 `sentry_sdk.capture_exception()` sites across 7 files + 3 in scripts/; documented retry-last-attempt discipline (`chesscom_client.py:100`, `lichess_client.py:126`); `_sentry_before_send` fingerprints transient DB errors (`main.py:23-39`). |
| Secrets / config | **A** | `.env`, `prod.env`, `.envrc` gitignored; only `.env.example` tracked. Pydantic-settings-driven config (`app/core/config.py:4-22`). CI uses GitHub Secrets for SSH. |
| Code smells | **A** | 0 `TODO`/`FIXME`/`XXX`/`HACK` in tracked source (the 4 hits are inside `reports/` from the prior audit file). |
| Maintainability / tests | **A** | 39 test files / 19,034 LOC against a real Postgres 18 container (CI service + `conftest.py:69-99`); CI gates ruff → ty → pytest → eslint → tsc → vitest → knip. |
| Security | **A−** | FastAPI-Users JWT + Google OAuth; CSRF double-submit cookie fix for CVE-2025-68481 with `secrets.compare_digest` (`auth.py:85-96, 141-147`); `send_default_pii=False` (`main.py:54`); IP rate limit on guest creation (`auth.py:225-229`). `decode_jwt` exception at `auth.py:132-137` catches bare `Exception` — intentional but coarse. |
| Database design | **A** | All FKs declare `ondelete="CASCADE"` (models verified individually); unique constraints on natural keys (`uq_games_user_platform_game_id`); deliberate types (`SmallInteger` for ply/material, `BigInteger` for Zobrist hashes, `Float(24)` for clock seconds); partial + covering indexes with `postgresql_where` / `postgresql_include` (`game_position.py:22-34`). |
| Frontend quality | **A−** | Strict TS with `noUncheckedIndexedAccess` (`tsconfig.app.json:21`); `theme.ts` centralizes colors (79 LOC); knip enforced in CI; `data-testid` conventions documented and applied; `Sentry.ErrorBoundary` at app root (`App.tsx:469`). Gap: no `React.lazy` anywhere — 0 lazy imports found. |
| Observability | **A−** | Sentry on both ends with `beforeSend` fingerprinting; `pg_stat_statements` preloaded (`docker-compose.yml:12-15`); self-hosted Umami analytics. No structured/JSON logging in backend — plain `logging.getLogger`. |
| Performance | **A−** | Fully async (no `requests`); 0 `asyncio.gather` calls on `AsyncSession`; deliberate batch tuning (10 → 28 games, `import_service.py:37`) with OOM rationale; Zobrist integer equality on indexed columns; covering indexes eliminate sequential scans for endgame aggregation. |
| Disaster recovery / backups | **B−** | Hetzner-managed daily VM snapshots, 7-day rolling (README:107-117); no `pg_dump` cron, no PITR / WAL archiving. Acknowledged as a gap in README. RPO up to 24 hours; no tested restore on record. |
| Data privacy / GDPR | **C+** | Privacy policy exists (`Privacy.tsx:1-80`); deletion is email-only (`support@flawchess.com`) — no in-app endpoint. `ondelete=CASCADE` on every user-owned table, so email-handler deletion would fully propagate, but the manual path is a friction gate for a GDPR-Art.17 request. No data export endpoint. |
| Dependency management | **C** | No `.github/dependabot.yml`, no `renovate.json`. Lockfiles committed and verified (`npm ci`, `uv sync --locked`). No `npm audit` or `pip-audit` step in CI. Docker base image is `python:3.13-slim` (tag, not SHA). |
| Frontend bundle / perf | **B−** | Production `index-CMxKKtn3.js` = 980 KB raw / 286 KB gz; CSS 96 KB / 16 KB gz. Single chunk — no route-based splitting, no lazy loading of recharts/react-chessboard. PWA with service-worker caching is correctly wired. |
| CI/CD execution speed | **A−** | Median 2:00-2:30 across last 20 main runs (e.g. 20:37→20:40 = 2:28, 18:49→18:51 = 1:40); backend + frontend serialized in one job. No pytest-xdist or vitest shard — fine at current scale. Deploy = `workflow_dispatch` only with post-deploy health check. |
| Technical debt / legacy stack | **A** | Python 3.13, Node 24, React 19, FastAPI 0.115, Vite 7, Tailwind 4, PostgreSQL 18, SQLAlchemy 2.x — all current majors. No archived/orphaned direct deps spotted. No deprecated-API usage or `# do not bump` blockers grep'd. |

> **Bottom line.** Production-grade for its footprint. The codebase punches above its weight: 39,500 LOC with a disciplined layering convention, a single shared filter utility, a real-Postgres test harness with a 48% test/code ratio, and type safety locked in on both ends (`ty` + `noUncheckedIndexedAccess`). The two meaningful gaps are supply-chain automation (no Dependabot/Renovate, no CVE audit in CI) and a heavy single-chunk frontend bundle (980 KB raw / 286 KB gz). GDPR deletion via email-only is acceptable for a solo project but would not survive a regulatory audit of a multi-staff org. Remaining work is refinement — Dependabot, code splitting, `pg_dump` as a second backup layer — not rescue.

[Read the full report →](./examples/flawchess_quality_assessment_2026-04-17.md)

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
