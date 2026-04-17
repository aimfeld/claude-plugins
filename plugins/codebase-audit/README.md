# codebase-audit

A [Claude Code](https://www.claude.com/product/claude-code) plugin that produces a thorough, evidence-based software quality assessment for any git repository — architecture, security, database design, observability, testing, disaster recovery, GDPR, dependency management, frontend bundle performance, and CI/CD speed.

Every grade and finding is backed by a concrete `file:line` pointer so a reviewer can verify any claim in under a minute.

## What you get

A single Markdown report (~3–6 pages) written to `reports/{project}_quality_assessment_{YYYY-MM-DD}.md`:

- **Summary stats** — LOC, test LOC, test/code ratio, coverage, commits in last 90 days, active contributors, primary languages
- **Executive summary** — graded table across 16 dimensions, with a 3–4 sentence bottom line
- **Operational picture** — numbered data-flow walkthrough (how the system actually runs)
- **Per-dimension findings** — each with `file:line` evidence
- **Substantial problems** — numbered, with effort estimates
- **What's notably good** — patterns worth keeping
- **Recommended actions** — Immediate / Short term / Medium term

## Example report

A full sample assessment of a production open-source codebase lives at [`../../examples/flawchess_quality_assessment_2026-04-17.md`](../../examples/flawchess_quality_assessment_2026-04-17.md). A taste:

### Summary stats (excerpt)

| Metric | Value | Notes |
|---|---|---|
| Total code LOC | ≈36,275 (Python 23,188 + TS 13,087) | `scc` exact counts |
| Test LOC | 17,806 across 36 files | Test/code ratio ≈ 49% |
| Test coverage | ≈89% backend | Read from existing `htmlcov/status.json` |
| Commits (last 90 days) | 765 | Very active |
| Active contributors (last 90 days) | 2 (same person, two emails) | Effectively single-maintainer |

### Executive summary (excerpt)

| Dimension | Grade | One-line finding |
|---|---|---|
| Architecture | **A−** | Router/service/repository layering followed consistently; `endgame_service.py` at 1,534 LOC is the one god-file outlier. |
| Security | **A−** | OAuth CSRF double-submit cookie cites CVE-2025-68481 (`auth.py:85-96`); no raw SQL; PII-off Sentry. |
| Database design | **A** | Every FK has explicit `ondelete=CASCADE` (6/6 models); deliberate `SmallInteger`/`Float(24)`/`BigInteger` choices. |
| Frontend quality | **A** | `strict` + `noUncheckedIndexedAccess` enabled; **zero** `as any` / `@ts-ignore`. |
| Disaster recovery | **B−** | Hetzner daily snapshots cover disk loss. No `pg_dump` second layer, no WAL archiving / PITR, no tested restore. |
| Dependency management | **C+** | Lockfiles verified in CI; **no Dependabot / Renovate**, no `pip-audit` / `npm audit` in CI. |
| Frontend bundle | **C+** | Main chunk is 998 KB raw / ≈285 KB gzipped. **Zero code-splitting** (no `React.lazy`). |

> **Bottom line.** FlawChess is a production-grade codebase on every axis relating to code craft: layering, DB design, type discipline, test coverage, Sentry wiring, and security fundamentals are all A-tier. The main finding a reviewer would flag is **no automated dependency updates and no vulnerability scanning in CI** — an unusual gap for a project otherwise this disciplined. Remaining work is closing those gaps, not rewriting anything.

[Read the full report →](../../examples/flawchess_quality_assessment_2026-04-17.md)

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

Grades on a standard A–F scale with `+`/`−` half-steps. Dimensions without enough evidence are marked `—` rather than guessed.

## Install

```
/plugin marketplace add aimfeld/claude-plugins
/plugin install codebase-audit@aimfeld
```

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
4. Probe each of the 16 dimensions with targeted greps and reads
5. Write the graded report to `reports/`

Typical run: 5–15 minutes on a medium-sized repo.

## Requirements

- [Claude Code](https://www.claude.com/product/claude-code)
- Bash (the stats collector is a shell script)
- Optional but recommended: `tokei` for accurate LOC breakdown. The stats collector offers to install it if missing.

Works on any language — Python, TypeScript/JavaScript, Go, Rust, Java, Ruby, PHP, C#, etc.

## License

MIT — see [LICENSE](../../LICENSE).
