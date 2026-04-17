---
name: report
description: Produce a thorough software quality assessment report for a git repository — covering code architecture, security, database design, observability, testing, frontend quality, deployment, disaster recovery, data privacy (GDPR), dependency management, frontend bundle performance, CI/CD execution speed, and technical debt / legacy-stack currency, plus summary stats (LOC, test LOC, test coverage, commit activity). Use this skill whenever the user asks for a "quality report", "quality assessment", "code audit", "codebase review", "technical due diligence", "production readiness review", "health check", "grade my codebase", or anything along the lines of "how good is this project", "what are the weak spots", "is this safe to deploy", or "assess/audit this repo". Works on any git repo regardless of primary language (Python, TypeScript/JavaScript, Go, Rust, Java, Ruby, PHP, C#, etc.). Writes the report to `reports/{project}_quality_assessment_{YYYY-MM-DD}.md`.
---

# Quality Assessment

Generate a production-readiness quality assessment for a git repository. The output is a markdown report with graded dimensions, concrete evidence cited to file:line, and an actionable "what to do next" list.

The report is meant to be read top-to-bottom by a technical stakeholder — a maintainer, a reviewer, or a potential contributor — in 15-20 minutes, and walk away with a calibrated picture of the codebase: what's strong, what's weak, what would a reviewer flag in due diligence, and what's worth fixing first.

## Core principle: evidence, not vibes

The value of this report is that every grade and every finding is backed by a concrete pointer into the codebase (`app/routers/auth.py:85-88`, `docker-compose.yml:12`, `.github/workflows/ci.yml:40`). A reviewer should be able to verify any claim in under a minute. If you can't cite evidence, say "not verified" — do not guess.

If you find yourself writing "seems to" or "probably has", that is a signal to go read the file. The difference between a good report and a generic one is whether every claim lands somewhere specific in the codebase.

## Workflow

Follow these steps in order. Do not skip the orient/stats phases — they calibrate the rest.

### 1. Orient

Identify the project before assessing it. Read these in parallel:

- `README.md` / `README.rst` — what does the project *do*?
- The primary dependency manifest(s) — `pyproject.toml`, `package.json`, `go.mod`, `Cargo.toml`, `pom.xml`, `build.gradle`, `Gemfile`, `composer.json`, `*.csproj`
- Top-level directory listing — is it monorepo, backend-only, frontend-only, library, CLI, service?
- Any `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `ARCHITECTURE.md`, `docs/` — authoritative context the project wrote about itself
- `Dockerfile`, `docker-compose*.yml`, `deploy/`, `.github/workflows/` — deployment and CI shape

From this, form a one-paragraph operational picture you can test against as you read code. Example: "FastAPI + React + PostgreSQL chess analyzer deployed to a single Hetzner box via GitHub Actions, Sentry on both ends, single-maintainer open source."

### 2. Gather stats

Run the stats script. It produces a snapshot of LOC, test LOC, coverage artifacts, git activity, dependency files, and CI timing — all the numeric inputs for the summary table at the top of the report.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/report/scripts/collect_stats.sh" /absolute/path/to/repo
```

The script writes a machine-readable summary to `/tmp/quality-assessment-stats.txt` and also prints it. Read the output and keep key numbers handy for the report.

If `tokei` is not installed, the script will ask whether to install it. Tokei gives accurate LOC with code/comment/blank split across languages; the fallback (`git ls-files` + `wc -l`) only gives a rough total. If the user declines, report stats as "approximate".

Test coverage: the script looks for existing coverage artifacts (`.coverage`, `coverage.xml`, `lcov.info`, `coverage/coverage-summary.json`, `htmlcov/`, Go coverprofile, etc.). It does **not** run tests — if no artifact exists, report coverage as "not measured" and recommend running coverage as a follow-up. Do not silently omit the coverage row.

### 3. Survey operational context

Before grading dimensions, build a mental map of how the system actually runs. Read:

- The main entry point(s) (`main.py`, `app.py`, `server.ts`, `main.go`, etc.)
- Database migration folder if one exists — migration count, whether `downgrade()` / rollback is implemented
- `.env.example` / config loader — how secrets and config are supplied
- Deploy entrypoint — `deploy/entrypoint.sh`, `Procfile`, `systemd` unit, `k8s/` manifests
- One representative file per layer (router/controller, service, repository/model) to sanity-check the architecture claim you will make

Capture the data flow in 3-5 numbered steps. This becomes section 2 of the report and anchors the rest.

### 4. Assess each dimension

Work through every dimension in `references/dimensions.md`. For each one:

1. Plan a small set of grep/glob/read probes that would answer the question
2. Run them (in parallel when independent)
3. Record the concrete evidence
4. Assign a grade (see "Grading rubric" below) and write a one-line finding

Grade honestly. Not every project is an A. A codebase that genuinely hasn't implemented backups, or has no dependency automation, or ships 2 MB of unused JS to mobile users, is a B or C in that dimension. The report is most useful when grades are calibrated, not uniformly inflated.

Per-language probes (what to grep for, which config files, which tools are idiomatic) live in `references/languages.md`. Read only the sections for languages actually present.

### 5. Write the report

Use the exact structure in `references/report-template.md`. Fill each section with findings from step 4, citing file:line. Do not invent sections the template does not have, and do not skip sections (if a section doesn't apply, say so explicitly with one sentence).

Save to `reports/{project-name}_quality_assessment_{YYYY-MM-DD}.md` (create the `reports/` directory if needed). Use the repo's directory name as `{project-name}`, lowercased and kebab-cased. Use today's date for `{YYYY-MM-DD}` so each run produces a timestamped, side-by-side report instead of overwriting the previous one.

### 6. Hand off

At the end of your turn, tell the user:
- The path of the report
- The overall picture in one sentence (e.g., "Production-grade with observability gaps", or "Healthy core, missing disaster recovery")
- The top 2-3 items from section 4 (Substantial Problems) they should look at first

## Dimensions (summary — see `references/dimensions.md` for what to check in each)

1. **Architecture & layering** — layer discipline, shared abstractions, router/controller conventions, separation of concerns
2. **Code duplication** — shared utilities vs copy-paste, single source of truth for core logic
3. **Error handling & observability** — Sentry/equivalent coverage, retry patterns, structured logging, metrics
4. **Secrets & configuration** — no hardcoded secrets, env-based config, no `.env` checked in
5. **Code smells** — magic numbers, TODO/FIXME, commented-out blocks, dead code
6. **Maintainability & tests** — test framework, real-DB vs mocks, test LOC ratio, test coverage %, CI gates (lint, type check, dead exports), **and IDE-committed inspection profiles (`.idea/inspectionProfiles/*.xml`, `.vscode/settings.json`, `.editorconfig`) as a weaker-but-real enforcement layer when CI is thin or absent**
7. **Security** — auth dependencies, CSRF/OAuth state, ORM-only vs raw SQL, CORS, sensitive-PII flags, known CVEs patched, input validation
8. **Database design** — FK constraints enforced at the **DB layer via migrations** (preferred) *or* ORM annotations — check migrations first before flagging ORM-only gaps; unique/natural-key constraints, deliberate column types, index strategy, migration rollback coverage
9. **Frontend quality** — strict TS, theme token centralization, accessibility attributes (`aria-label`, semantic HTML), dead-export detection
10. **Observability** — logging format, request correlation, Sentry `before_send` fingerprinting, slow-query logs, metrics endpoints
11. **Performance** — N+1 patterns, async correctness, blocking I/O in async paths, batching, OOM mitigations
12. **Disaster recovery & backups** *(critical for production deployments)* — scheduled DB backups, offsite storage, restore documentation, PITR / WAL archiving, tested restore
13. **Data privacy & GDPR/FADP** *(critical if storing PII or third-party data)* — account deletion endpoint, data export, consent flows, privacy policy link, erasure path actually reaches every user-owned table (via DB cascade, ORM cascade, *or* application-code purge — any one is acceptable)
14. **Dependency management & supply chain** — Dependabot / Renovate configured, lockfiles committed and verified in CI, `npm audit` / `pip-audit` / equivalent, pinned base images in Dockerfile
15. **Frontend bundle & performance** *(if a frontend exists)* — production bundle size, code splitting / lazy loading of heavy libs, tree-shaking, source-map discipline, Lighthouse-class red flags
16. **CI/CD execution speed** — workflow duration, test parallelization (`pytest-xdist`, `vitest --shard`, `go test -parallel`), caching of deps/build artifacts, deploy automation
17. **Technical debt & legacy stack** — language-runtime currency vs active support windows, framework major-version distance from latest, legacy-language/framework exposure (AngularJS, CoffeeScript, class components in a hooks codebase), upstream maintenance status of direct dependencies (archived / orphaned / last-release staleness), deprecated-API usage, blocked-upgrade signals

Dimensions 12-17 are the ones most commonly missed in ad-hoc code reviews. Treat them as first-class and always include them in the report, even when the answer is "not applicable" (e.g. no frontend → say so in the frontend bundle row).

## Grading rubric

Use a standard five-tier scale. Attach `+` or `−` to a letter for half-steps.

| Grade | Meaning |
|---|---|
| **A** | Genuinely best-practice. Nothing a reviewer would flag. |
| **B** | Solid, with known small gaps. "Would ship, would note the gap in the PR." |
| **C** | Works but has real rough edges. "Ship with ticket to fix." |
| **D** | Risky. "Don't ship until this is fixed." |
| **F** | Broken or absent in a way that blocks production use. |

Calibration anchors:

- A dimension is **A** only if the evidence is overwhelming and the pattern is followed *everywhere*, not just in one file you spot-checked.
- "Mandatory FKs with `ondelete`" is A only if *every* FK has it. One bare FK → A−. Three or more → B+.
- A dimension with a missing obvious element (no backups, no account deletion, no Dependabot) starts at C regardless of how nice the rest is.
- **A− is the correct grade when the pattern holds everywhere except for one named, acknowledged outlier** (e.g., architecture is clean across 20 files but one 1,500-LOC god-file bundles three concerns; secrets are handled right but one dev-only literal password sits in a seed script). Name the outlier explicitly in the finding. Don't give A in this case, and don't drop to B+ unless there are multiple outliers or the outlier is load-bearing.

Do **not** grade any dimension you couldn't gather evidence for. Mark it `—` and explain in one sentence why you couldn't assess it.

## Report structure

Full template: `references/report-template.md`. At a high level:

1. **Header table** — date, scope, author, generation method
2. **Summary Stats** *(new)* — LOC, comment LOC, test LOC, test/code ratio, test coverage, commits in last 90 days, active contributors, primary languages
3. **Executive Summary** — grade table across all 17 dimensions, plus a 3-4 sentence "bottom line"
4. **What the app does — Operational Picture** — numbered data-flow walkthrough, including a "Disaster Recovery & Backups" subsection
5. **Code Quality Findings** — one subsection per dimension with concrete evidence
6. **Substantial Problems Worth Addressing** — concrete, numbered, with effort estimates
7. **What's Notably Good** — patterns worth keeping, reusing, copying to other projects
8. **Recommended Actions** — Immediate / Short term / Medium term buckets. Always include "Dependency Updates (Dependabot/Renovate)" in at least the short/medium term if not already in place.
9. **Bottom Line** — one-paragraph verdict

## Writing style

- Concrete > generic. "All six repositories import from `app/repositories/query_utils.py:12`" beats "shared filter utilities are used consistently".
- Cite file:line for every non-trivial finding. `auth.py:85-96` is precise enough to verify.
- Prefer quantified claims: "11 `capture_exception()` sites across 8,600 LOC", not "Sentry coverage is thin".
- Use m-dashes sparingly. Prefer commas, periods, or colons.
- Do not open with sycophancy. No "This is an impressive codebase!" — get to the substance.
- Flag uncertainty explicitly: "Not verified", "Spot-checked only", "Based on 3 sampled files out of 47".
- Do not invent features. If the repo has no frontend, the "frontend quality" grade is `—` with a one-line explanation.
- Do not add emojis unless the repo itself uses them heavily.

## Edge cases & common pitfalls

- **Monorepo**: Detect subprojects (`packages/*`, `apps/*`, separate `package.json` trees). Either grade the subprojects separately (sections 3-5 per sub-project) or focus on the primary one and note which you focused on. Do not silently blend numbers from multiple subprojects.
- **Library / SDK / CLI (not a service)**: Dimensions 12 (DR/backups), 13 (GDPR), 15 (frontend bundle) often don't apply. Mark as `— N/A: library does not store user data` and keep going.
- **Greenfield repo with no production deployment**: Grade what exists honestly, but label the report "Pre-production assessment" in the header. Do not penalize for missing backups when there is nothing in production to back up; do note the gap as a blocker for launch.
- **Very large repo (> 100k LOC)**: Do not try to read everything. Pick one representative file per layer per major concern, spot-check, and say "spot-checked" in the report. Lean harder on grep/glob aggregate counts.
- **Languages the skill-runner doesn't know well**: Still run the stats script, still grade the universal dimensions (secrets, dependency management, CI/CD, DR). For language-specific dimensions, read `references/languages.md` for that language and follow its probes literally.
- **No README**: Say so in the operational picture. It is itself a finding worth noting (B− or C in maintainability).
- **Private / closed-source repo**: Same report; just be extra careful not to include literal secrets (even if accidentally committed) in the output. Redact to `<REDACTED: looks like a real key>` and note that the secret was found.

## Files in this skill

- `SKILL.md` — this file, the entry point and workflow
- `references/report-template.md` — the exact markdown template to fill in
- `references/dimensions.md` — what to check and how to grade per dimension
- `references/languages.md` — per-language probes, idioms, and tool pointers
- `scripts/collect_stats.sh` — bash script to gather LOC, coverage, git activity, CI timing

Read the reference files when you hit the relevant step — you don't need them loaded upfront.