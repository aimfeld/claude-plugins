# Report Template

This is the exact structure to use when writing the final report. Do not reorder sections, do not add sections not listed here, do not skip sections (use `— N/A: <reason>` for rows that don't apply).

Save the filled-in report to `reports/{project-name}_quality_assessment_{YYYY-MM-DD}.md` (use today's date, so repeat runs produce timestamped side-by-side reports rather than overwriting the previous one).

---

```markdown
# Quality Assessment — `{project-name}` {one-line project description}

| Field  | Value                                                                                       |
|--------|---------------------------------------------------------------------------------------------|
| Date   | {YYYY-MM-DD}                                                                                |
| Scope  | `{/absolute/path/to/repo}` (summary from stats script — e.g., "≈8,600 LOC backend Python, ≈13,400 LOC TypeScript, 32 test files / ≈14,000 LOC of tests") |
| Author | {generator identity with plugin version — e.g., "Claude (Opus 4.7) via the `codebase-audit:report` skill (v{X.Y.Z})". Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` to get the version field.} |
| Method | Static analysis of the repository at commit `{short-sha}` on branch `{branch}`. {"No tests were run." OR "Test suite run; {passed/total} passed, coverage {X%} — see §1."} |

**Context.** {2-4 sentence paragraph describing what the project does, who it serves, and the stack. Pull from README/CLAUDE.md. Include deployment shape if known (e.g., "Single-box Hetzner deployment behind Caddy"). This is the reader's orientation — get it right.}

---

## Method & Limitations

*(This block is mandatory. It preempts the "is this an audit?" question a reader asks within 30 seconds of opening the report.)*

**What this is.** A senior-engineer static review of a git repo at a specific commit, produced by Claude via the `codebase-audit:report` skill in minutes. Every non-trivial claim cites `file:line` so a reviewer can verify each finding in under a minute.

**What this is not.** Not a formal audit. No interviews with the development team. No legal or professional accountability. No ISO 25010 weighted-scoring methodology. No dynamic penetration testing or load testing. Use this as a first-pass engineering review, not as a substitute for an investor-grade or compliance-grade assessment.

**Confidence levels.** Each finding in the §5 Findings Register is tagged with one of three confidence levels (applies to individual *claims*):

- **Verified** — claim backed by end-to-end reading of the cited file(s).
- **Likely** — claim backed by spot-check of representative files, or strongly implied by configuration.
- **Inferred** — claim backed by absence of contrary evidence (e.g., "no `.github/workflows/` found → no CI"). Inferred ≠ wrong, but is the most likely to miss something the repo's maintainers know that the static analysis cannot see.

**Section assessability.** Each row in §1 Summary Stats carries one of three assessability tiers (applies to *whole sections* — a step above claim-level confidence):

- **Measured** — we ran the tool or parsed the artifact (e.g., coverage artifact exists and was read; tests were executed).
- **Inferred from artifacts** — we read configs and lockfiles but didn't execute anything (e.g., "Dependabot configured" from `.github/dependabot.yml` presence; "Maintainability-test design" from test-file shape without running them).
- **Not assessable without setup** — the probe requires tooling or deps that aren't installed in this environment. State what *would* be needed to upgrade the row to Measured (e.g., "install `node_modules/` then re-run with `SIGNAL_TEST_DEPS_INSTALLED=yes`").

A finding sourced from a "Not assessable" section must not exceed **Inferred** in §5.

**Environment tier.** {Copy the `ENVIRONMENT_TIER` value and `TIER_REASON` from `collect_stats.sh` output — e.g., "warm — LOC tool on PATH and at least one test runner has its deps installed." / "partial — test runners detected but deps not installed." / "cold — no LOC tool on PATH and no test runner with installed deps." This line tells the reader which §1 rows will read as `Not assessable without setup`.}

**Dynamic validation.** {One of:
- "No tests were run; the Maintainability grade reflects static inspection of the test suite only."
- "Backend suite: {N passed / M total}, coverage {X%}. Frontend suite: {N passed / M total}, coverage {X%}. Per-suite details in §1 Summary Stats. Results are separate from the Maintainability grade, which reflects test-suite design, not runtime pass/fail."
- "Partial: backend suite run ({N/M, X%}); frontend suite skipped (deps not installed / user declined)."
- "Not assessable without setup — environment is `cold`; no test runner has its deps installed." }

**Grade rubric.** A = best-practice everywhere. B = solid with small known gaps. C = works but has real rough edges. D = risky, don't ship. F = broken or absent. `+` / `−` denote half-steps; a dimension drops one tier for each missing obvious element (no backups, no deps automation, etc.). See the §2 Executive Summary table for the per-dimension grades.

---

## 1. Summary Stats

| Metric | Value | Notes |
|---|---|---|
| Total code LOC | {N} | {language breakdown, e.g., "Python 8,600 / TypeScript 13,400 / SQL 420"} |
| Comment LOC | {N} ({X}%) | {"density looks healthy" / "very sparse" / "tokei not installed, approximate"} |
| Test LOC | {N} ({X}% of code LOC) | {"32 pytest files; high ratio reflects integration-test style" etc.} |
| Test suite run — {suite name, e.g. backend} | `Not executed` or `{X passed / Y total, Z failed, Wskipped, coverage Z%}` | {exact command used + source, e.g. "`uv run pytest --cov=app` (README line 73)" — or "Skipped: deps not installed" / "Skipped: user declined"} |
| Test suite run — {suite name, e.g. frontend} | `Not executed` or `{...}` | {exact command used + source — e.g. "`cd frontend && npx vitest run --coverage` (frontend/package.json script)". Add one row per suite in a monorepo; delete this row if project has only one suite.} |
| Test coverage | {X%} or `Not measured` | {coverage source file, or "no .coverage / lcov.info found — run `pytest --cov` to measure". In a monorepo, the per-suite rows above are the authoritative numbers; this row stays "Not measured" unless a single aggregate exists.} |
| Commits (last 90 days) | {N} | {pace note, e.g., "active, single maintainer"} |
| Active contributors (last 90 days) | {N} | — |
| Primary languages | {list, e.g., "Python, TypeScript, SQL"} | — |
| Total files tracked | {N} | — |
| Dependency manifests | {list, e.g., "pyproject.toml, package.json"} | — |
| Lockfiles present | {Yes/Partial/No} | {e.g., "uv.lock + package-lock.json, both committed"} |

If any row is not `Measured`, tag it explicitly with one of the three assessability tiers from the Method & Limitations block — `Measured`, `Inferred from artifacts`, or `Not assessable without setup` — and explain why in the Notes column. Do not silently omit. Rows that could not be reached because of a `cold` environment tier should read `Not assessable without setup (environment tier: cold)` so the reader immediately understands what a different environment would change.

---

## 2. Executive Summary

| Dimension | Grade | One-line finding |
|---|---|---|
| Architecture | **{A/B/C/D/F}** | {one line with evidence pointer} |
| Code duplication | **{grade}** | {one line} |
| Error handling / Observability | **{grade}** | {one line} |
| Secrets / config | **{grade}** | {one line} |
| Code smells | **{grade}** | {one line} |
| Maintainability / tests | **{grade}** | {one line} |
| Security | **{grade}** | {one line} |
| Database design | **{grade or `— N/A`}** | {one line or N/A reason} |
| Frontend quality | **{grade or `— N/A`}** | {one line or N/A reason} |
| Observability | **{grade}** | {one line} |
| Performance | **{grade}** | {one line} |
| Disaster recovery / backups | **{grade}** | {one line — this is often the weakest row, grade honestly} |
| Data privacy / GDPR | **{grade or `— N/A`}** | {one line or N/A reason} |
| Dependency management | **{grade}** | {one line — "Dependabot active" or "No automation detected"} |
| Frontend bundle / perf | **{grade or `— N/A`}** | {one line or N/A reason} |
| CI/CD execution speed | **{grade}** | {one line — include observed duration if measurable} |
| Technical debt / legacy stack | **{grade}** | {one line — e.g., "Python 3.12, Node 20 LTS, React 19, no archived deps" or "Python 3.8 EOL; Django 3.2 two majors behind; `request` (archived) still in use"} |

**Bottom line:** {3-5 sentences. Lead with the overall verdict (production-grade / healthy with gaps / needs work before launch). Name 1-2 standout strengths. Name the top 1-2 weakest dimensions. Close with "remaining work is [refinement / rescue / closing a specific gap]".}

---

## 3. What the App Actually Does — Operational Picture

{Numbered data-flow walkthrough, 5-8 steps. Each step cites the service/module that owns it. This is where the reader builds the mental model.}

1. **{Step name}** via `{file:line}`: {what happens}
2. **{Step name}** (`{service}.py`): {what happens}
...

### Deployment & infrastructure

- Stack: {languages, frameworks, database, web server, reverse proxy}
- Host: {single box / Kubernetes / serverless / local-only}
- Deploy flow: {how code reaches production — GitHub Actions, manual, etc.}
- CI workflow: `{.github/workflows/*.yml}` — {gates: lint, type check, tests, etc.}

### Disaster Recovery & Backups

{This subsection is mandatory. State what you found even if the answer is "nothing".}

- **Database backups:** {scheduled via ... / manual only / none detected}
- **Offsite storage:** {S3 / Hetzner Storage Box / B2 / not configured}
- **Point-in-time recovery:** {WAL archiving on / off / N/A for non-Postgres stacks}
- **Restore procedure documented:** {yes — link / no}
- **Last tested restore:** {date or `unknown` or `not tested`}
- **RPO / RTO targets:** {stated or `not defined`}

If the repo contains no indication of a backup strategy, state that explicitly. This is a blocker-class finding for production systems that store user data.

**Key insight.** {One paragraph naming the central architectural bet — the thing that, if it broke, would force a rewrite. Examples: "Zobrist-hash position matching", "event-sourced ledger", "generated SQL client from OpenAPI", "Rails-style convention over configuration". Say whether it holds up.}

---

## 4. Code Quality Findings

Organize as subsections per dimension. Include every dimension from section 2 (grade table). Each subsection should be 3-10 bullet points with file:line evidence.

### 4.1 Architecture and layering

{Bullets with file:line evidence. Name the conventions you see and whether they are followed.}

### 4.2 Code duplication

{Grep aggregate counts where possible. "Six repositories all import from `query_utils.py:12` — single source of truth." or "Same filter logic duplicated in 4 controllers — see `X.java:45`, `Y.java:78`, `Z.java:91`, `W.java:112`."}

### 4.3 Error handling and observability

{Sentry / equivalent coverage. Count `capture_exception()` sites. Note retry-loop discipline. Flag `except:` without type or action.}

### 4.4 Secrets and configuration

{Grep for high-entropy strings, checked-in `.env`, hardcoded API keys, JWT secrets. If clean, say "No hardcoded secrets found in tracked files (`git grep` for common patterns returned only placeholders)."}

### 4.5 Code smells

{TODO/FIXME/XXX count. Dead code blocks. Magic numbers. Comment hygiene.}

### 4.6 Maintainability and tests

{Test file count, LOC ratio, framework, real-DB vs mock approach, coverage %. CI gate list (lint/type check/dead exports). Migration discipline if applicable.}

### 4.7 Security

{Auth dependencies applied uniformly, CSRF/OAuth state, CORS, ORM-only vs raw SQL, PII handling, known CVE patches.}

### 4.8 Database design

{FK/ondelete discipline, unique constraints on natural keys, index strategy on hot paths, column-type intentionality, migration rollback coverage. If no DB: mark N/A.}

### 4.9 Frontend quality

{Strict TS, theme centralization, semantic HTML, `aria-label` on icon-only buttons, `data-testid` discipline, dead-export detection. If no frontend: mark N/A.}

### 4.10 Observability

{Logging format (plain vs JSON), request correlation, Sentry `before_send` fingerprinting, slow-query logs, metrics endpoints, uptime monitors.}

### 4.11 Performance

{N+1 awareness, async safety, blocking I/O in async paths, batching, OOM mitigations, caching.}

### 4.12 Disaster recovery and backups

{Concrete findings. Name specific mechanisms (cron job, managed service, script) and their target (S3 bucket, storage box, local disk only). Grade on: is there a backup at all, is it offsite, is restore documented, is restore tested. Absence of any of these drags the grade down — a project with "no backups configured" cannot be above C here.}

### 4.13 Data privacy and GDPR/FADP

{Does an account-deletion endpoint exist? Grep for `DELETE /users/me`, `delete_account`, `deleteAccount`, `hard_delete`. Check whether the `ondelete=CASCADE` schema discipline is actually wired to a user-facing action. Consent flows on signup. Privacy policy link. Data export endpoint. If the app stores no PII, mark N/A and say why.}

### 4.14 Dependency management and supply chain

- **Automation:** {`.github/dependabot.yml` present? `renovate.json`? schedule?}
- **Lockfiles:** {`uv.lock` / `package-lock.json` / `go.sum` / `Cargo.lock` — committed? verified in CI via `npm ci` / `uv sync --locked`?}
- **Audit tooling in CI:** {`npm audit` / `pip-audit` / `cargo audit` / `govulncheck` — running in CI?}
- **Base image pinning:** {Dockerfile uses `python:3.13-slim` by tag or `@sha256:...` digest?}
- **Transitive CVE exposure:** {spot-check count of flagged advisories if easy to obtain}

### 4.15 Frontend bundle and performance

{If a frontend exists, build it (or read the most recent build artifact) and report:}

- **Production bundle size:** {total `dist/` size and gzipped size of largest chunks, e.g., `index-abc123.js` = 420 KB / 140 KB gz}
- **Code splitting / lazy loading:** {React.lazy / dynamic import / route-level splitting? heavy libs (charts, 3D, chess boards) loaded only when needed?}
- **Tree-shaking hygiene:** {sideEffects set correctly, no barrel-file re-exports that pull in dead code, named imports used}
- **Source map exposure:** {not deployed to production, or deployed intentionally with Sentry uploads}

If no frontend exists: `— N/A: backend-only service`.

### 4.16 CI/CD execution speed

- **Observed workflow duration:** {pull last 5 `main`-branch runs via `gh run list` and report median duration if the repo uses GitHub Actions — e.g., "6m42s median across last 5 runs"}
- **Test parallelization:** {pytest-xdist / vitest shard / go test -parallel / jest --maxWorkers — enabled?}
- **Dependency caching:** {`actions/setup-*` cache keys, uv cache, npm cache — enabled?}
- **Matrix / sharding:** {tests split across jobs?}
- **Deploy automation:** {manual `workflow_dispatch` / auto on push / tagged releases only}

### 4.17 Technical debt and legacy stack

- **Language runtime versions:** {e.g., "Python 3.12 (`requires-python = ">=3.12"` in `pyproject.toml`), Node 20 LTS (`engines.node = ">=20"` in `package.json`)" — or flag: "Python 3.8 (`.python-version:1`) — EOL October 2024"}
- **Framework majors vs latest:** {e.g., "React 19, Next.js 15, FastAPI latest" — or flag: "React 16 (two majors behind current 19); Django 3.2 (two LTS lines behind)"}
- **Legacy-technology exposure:** {list anything load-bearing in a legacy tech — AngularJS, CoffeeScript, jQuery in a modern SPA, moment.js, class components in a hooks codebase — or "None detected"}
- **Dependency maintenance status:** {name the bulk check you ran (`npm outdated` + `npm ls` for Node, `pip list --outdated` + `pip-audit` for Python, `cargo outdated`, `bundle outdated`, `composer outdated --direct`, `go list -m -u all`) and summarize what it surfaced. List any direct dep that is registry-deprecated, archived on GitHub (`archived: true`), classified PyPI `Development Status :: 7 - Inactive`, or last-released > 18 months ago — with canonical successor where one exists, e.g., "`request` (archived 2020 → `undici`)", "`moment` (maintenance-only → `date-fns` / `Temporal`)". "No unmaintained direct dependencies detected via `npm outdated` + archive spot-check" if clean.}
- **Deprecated APIs in use:** {e.g., `componentWillMount`, `asyncio.get_event_loop()` in 3.12+, Django `url()`, Rails `before_filter` — or "None in new code"}
- **Build tooling currency:** {e.g., "Vite 5, uv, pnpm" — or flag: "webpack 4 (webpack 5 has been out since 2020)"}
- **Blocked upgrades:** {grep for `# do not bump`, `// locked to`, upgrade-blocker TODOs; list each with the reason if stated}

---

## 5. Findings Register

A consolidated, machine-readable view of every finding a reviewer would track. Rows are drawn from §4 subsections; this table exists so a reader can triage without reading the full narrative. High/Critical rows must reappear in §6 Substantial Problems; Medium/Low roll into §8 Recommended Actions.

**Severity**: Critical = production-blocking or data-loss risk; High = likely to cause incidents within 3 months; Medium = real risk but bounded; Low = minor quality/hygiene.
**Confidence** (from Method & Limitations block): Verified / Likely / Inferred. A finding whose source §1 row is `Not assessable without setup` must not exceed **Inferred** — if the audit couldn't measure it, downstream claims are at best inferential.
**Effort**: ≤1h / half-day / 1d / >1d.

| ID | Dimension | Finding | Severity | Confidence | Evidence | Effort |
|---|---|---|---|---|---|---|
| F-01 | {dim} | {one-line finding} | {Critical/High/Medium/Low} | {Verified/Likely/Inferred} | `{file:line}` | {≤1h / half-day / 1d / >1d} |
| F-02 | ... | ... | ... | ... | ... | ... |

Aim for 10–25 rows. Not every §4 bullet becomes a row — only findings a reviewer would actually file as a ticket. If a dimension has no ticket-worthy findings, it simply has no rows here (don't add filler).

---

## 6. Substantial Problems Worth Addressing

Concrete items a reviewer would file as tickets. Numbered, with an effort estimate and a rationale. Every Critical and High row from §5 must appear here.

1. **{Problem title}.** {2-3 sentences describing the gap and why it matters. Cite the evidence. Suggest a minimal fix.} *(effort: {≈X minutes/hours}, maps to §5 F-0N)*
2. ...

Aim for 4-8 items. Do not pad with trivia.

---

## 7. What's Notably Good

Patterns worth keeping and copying. 4-8 bullets. Be specific — "Zobrist-hash position matching" or "single `apply_game_filters()` utility" is better than "good code organization".

- **{Pattern name}** — {why it's notable, one-line evidence pointer}
- ...

---

## 8. Recommended Actions

Three time-boxed buckets.

### Immediate (this week — small, high signal)

1. {Action, effort, expected payoff}
2. ...

### Short term (this month — quality-of-life)

3. ...

### Medium term (next quarter — only if needed)

N. **Dependency updates (Dependabot / Renovate)** — {if not already in place, include this here at minimum; for a single-maintainer project it is the cheapest way to stay ahead of CVEs}
N+1. ...

---

## 9. Bottom Line

{One paragraph, 4-6 sentences. Final verdict. Who should read this codebase top-to-bottom? What should they expect? Is there a rewrite hiding in here, or is this "make a good thing better" territory? Close with a single sentence the user can quote.}
```

---

## Notes for the skill-runner

- The **Author row** must include the plugin version. Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`, pull the `version` field, and substitute into the Author cell as `Claude (Opus 4.7) via the \`codebase-audit:report\` skill (vX.Y.Z)`. This makes every saved report self-identifying.
- The **Method & Limitations block** (between Context and §1) is mandatory. Fill the "Dynamic validation" bullet based on whether Step 2b ran: if tests were run, state pass/fail + coverage; if not, state "No tests were run." Also fill the "Environment tier" line by copying the `ENVIRONMENT_TIER` and `TIER_REASON` emitted by `collect_stats.sh` — every report must carry this so the reader can tell whether an empty row is a gap in the project or a gap in the environment that ran the audit.
- The **Summary Stats** table (§1) is mandatory. "Test suite run" and "Test coverage" rows default to `Not executed` / `Not measured`; only populate with numbers when Step 2b ran successfully.
- The **Disaster Recovery & Backups subsection** (§3) is mandatory. If you cannot find evidence of a backup strategy, say so explicitly — do not omit the subsection.
- The **dimension grade table** (§2) must include all 17 dimensions, including the newer ones (12-17). Use `— N/A` with a reason for rows that don't apply to this project type.
- When a dimension is listed in the executive summary table, it must have a corresponding subsection in §4. Do not grade something in §2 and then skip it in §4.
- The **Findings Register** (§5) is mandatory. 10–25 rows, drawn from §4 subsections; each row needs Severity × Confidence × Evidence × Effort. Every Critical and High row must reappear in §6.
- §6 Substantial Problems items should be actionable. "Improve observability" is not actionable; "Add `sentry_sdk.set_context()` at the top of the 4 long-running service entry points, ≈ 1 hour" is.
- §8 Recommended Actions medium-term bucket should mention Dependabot / Renovate explicitly if the project lacks automated dependency updates.