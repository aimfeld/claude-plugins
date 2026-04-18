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

Test coverage: the script looks for existing coverage artifacts (`.coverage`, `coverage.xml`, `lcov.info`, `coverage/coverage-summary.json`, `htmlcov/`, Go coverprofile, etc.). It does **not** run tests by itself — if no artifact exists, report coverage as "not measured" and proceed to Step 2b (optional test run) before falling back to "not measured".

**Environment tier.** The script ends with an `ENVIRONMENT_TIER: warm|partial|cold` line plus per-signal flags (`SIGNAL_LOC_TOOL`, `SIGNAL_TEST_RUNNER_DETECTED`, `SIGNAL_TEST_DEPS_INSTALLED`). Read these before Step 2b — they decide the branch you take and the "Environment tier" row in the report's Method & Limitations block. The tiers:

- **warm** — an LOC tool is on PATH AND at least one detected test runner has its deps installed. Run tests per suite with user approval.
- **partial** — the environment is missing at least one capability (LOC tool absent, OR test runners detected but deps not installed, OR no test runners in a language where the audit usually has them). Ask the user *once* (Step 2b.1a below) whether to install, skip-but-run-what's-possible, or skip Step 2b entirely. Do not ask per suite.
- **cold** — no LOC tool AND no runner with installed deps. Skip Step 2b; mark dynamic-validation rows in §1 as `Not assessable without setup` and name the missing tooling.

### 2b. Offer to run the test suite *(optional)*

This step turns a pure-static report into one with dynamic-validation data points — one per test suite in the project. It is **opt-in per suite** — always ask the user first, and skip cleanly when dependencies are not installed or the project's test commands aren't discoverable.

**Orchestration, not rigid detection.** `collect_stats.sh` surfaces *signals* (root-level runners, nested `package.json`/`phpunit.xml`/`pyproject.toml`, README test headings, Makefile targets, package.json scripts). You assemble those signals plus a read of the project's own docs into concrete commands. **Do not guess commands** — use the ones the project documents.

#### Step 2b.1 — Gather the command candidates

Read these, in order, before proposing anything:

1. The "Test runner detection" section of `/tmp/quality-assessment-stats.txt` (root-level runners + nested/monorepo scan).
2. The "Test-command hints" section — in particular, the README headings, Makefile/Taskfile targets, and `package.json`/`composer.json` script lists.
3. The README sections the hints surfaced (e.g., "Running Tests", "Test Coverage") — read those lines in the README directly, don't paraphrase.
4. For a Python project: whether `uv.lock` / `poetry.lock` / `Pipfile.lock` is present (influences the runner prefix: `uv run pytest` vs `.venv/bin/pytest` vs `poetry run pytest`).
5. For a monorepo: treat each suite separately (e.g., backend `pytest`, frontend `vitest`). Each gets its own row in §1 and its own pass/fail + coverage number.

#### Step 2b.1a — Environment-tier gate (one question, not per-suite)

Before proposing individual suites, branch on `ENVIRONMENT_TIER` from the stats output. This consolidates what would otherwise be N install-or-skip prompts into a single decision — the audit stays a conversation, not an interrogation.

- **`warm`** — deps are installed for at least one suite. Proceed directly to Step 2b.2 and ask per-suite Run/Skip as before. No consolidated question needed.

- **`partial`** — at least one gap. Compose the install plan *from the repo's own docs* (the README "Running Tests" section the stats script surfaced, the Makefile / Taskfile target, the `package.json` script — **do not guess commands**), then ask the user once via `AskUserQuestion` with these options:
  - **Install missing deps, then run tests** — list the exact commands you would run (e.g., `cd frontend && npm install`, `composer install`, `uv sync`). Cite the source of each command (README line, Makefile target, script name). If no documented command exists for a gap, say so and do not offer to install it.
  - **Skip install, run only suites whose deps are already installed** — proceed to Step 2b.2 but silently mark the non-runnable suites as `Not executed (deps not installed)` in §1.
  - **Skip Step 2b entirely** — mark all dynamic-validation rows as `Not executed (user declined)` and continue to Step 3.

  If the user picks "Install", run the quoted commands (with permission) in the target repo, then re-run `collect_stats.sh` to refresh the tier — do not assume install succeeded, verify by reading the new tier line. If the re-run still reports `partial`, note which suites are still blocked and proceed with what's runnable.

- **`cold`** — nothing dynamic can be measured. Skip Step 2b entirely. Mark every dynamic-validation row in §1 as `Not assessable without setup` with the tier reason (copy from `TIER_REASON` in the stats output). The Method & Limitations block's "Environment tier" row records this so the reader knows the audit's envelope up front.

The single install-or-skip question is the only install prompt for the whole audit. Do not re-ask per suite in Step 2b.2.

#### Step 2b.2 — Propose commands to the user

For each candidate suite, propose the exact command you plan to run, citing where you got it (README line, Makefile target, package.json script). Use `AskUserQuestion` with one question per suite, each with two options: `Run` / `Skip`.

Example question for flawchess:

> **Backend test suite.** The README (lines 73-87) documents `uv run pytest --cov=app --cov-report=term-missing`. Run it now with a 5-minute timeout? (Run / Skip)

> **Frontend test suite.** `frontend/package.json` has `"test": "vitest run"`. To capture coverage: `cd frontend && npx vitest run --coverage`. Run it now with a 5-minute timeout? (Run / Skip)

If there is no documented command and you'd have to improvise — skip that suite and note "Command not documented" in the Method block. Do not invent commands.

#### Step 2b.3 — Run only what the user approved

For each approved suite:

1. Capture `git -C {repo} status --porcelain` output. Save it.
2. Run the command under `timeout 300 …` from the appropriate working directory (use `cd` if the command needs it, like `cd frontend && …`).
3. Parse the output for: total tests, passed, failed, skipped, duration, coverage %. Every test runner uses a different format; read the raw output yourself, don't assume a schema.
4. Capture `git -C {repo} status --porcelain` again. If it differs from the pre-run state, **discard the results** and record "test suite appeared to modify the working tree — results discarded, rerun manually".
5. If the run exited non-zero but all tests passed (e.g., a shellcheck error from a wrapper), still report passed/total — but flag "exit code non-zero, investigate" in the Method block.

#### Step 2b.4 — Write the results

Per approved suite, add one row to §1 Summary Stats:

| Test suite run — backend | `172 passed / 172, coverage 78%` | `uv run pytest --cov=app` (from README line 73) |
| Test suite run — frontend | `43 passed / 45, 2 failed, coverage 61%` | `cd frontend && npx vitest run --coverage` (from frontend/package.json) |

Update the Method & Limitations block's "Dynamic validation" line with per-suite summary (e.g., "Backend: 172 passed / 172, 78% cov. Frontend: 43 passed / 45, 2 failed, 61% cov."). Update the Method cell in the header table likewise.

#### Hard rules (unchanged)

- **Never install dependencies.** If the hints say deps aren't installed for a suite, skip that suite and say so.
- **Never modify the target repo.** The pre/post `git status --porcelain` check is the guard.
- **Never use test results to override the Maintainability grade.** That grade is about test-suite design (coverage, integration vs unit, CI gating); pass/fail is a separate, empirical data point reported alongside.
- **Time-box each suite to 5 minutes.** If exceeded, abort that suite and record "Timed out after 5 min" — but continue to other suites.
- If a suite is declined, skipped, or errored: report that suite's row as `Not executed` with the reason. Other suites are unaffected.
- If *all* suites are skipped: report coverage as "Not measured" in §1 and add "No tests were run." to the Method & Limitations block. Proceed to Step 3.

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

**Author field.** Read `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` and substitute the `version` field into the Author row, producing e.g. `Claude (Opus 4.7) via the codebase-audit:report skill (v0.3.0)`. Every saved report must carry the plugin version so readers can tell which revision of the skill produced it.

**Method & Limitations block.** Mandatory. Sits between the Context paragraph and §1 Summary Stats. Fill the "Dynamic validation" line based on whether Step 2b ran — pass/fail + coverage if it did, "No tests were run" otherwise. Also fill the "Environment tier" line by copying the `ENVIRONMENT_TIER` value and `TIER_REASON` from the stats output; for a `cold` or `partial` tier, this line tells the reader which rows in §1 are `Not assessable without setup` and why. Do not paraphrase the grade rubric; copy it from the template verbatim so the ladder is consistent across reports.

**Findings Register (§5).** Mandatory. Populate with 10–25 rows drawn from §4 subsections — only findings a reviewer would actually file as a ticket. Every row needs Severity × Confidence × Evidence × Effort. Every Critical and High row must reappear in §6 Substantial Problems. This is the single most important addition over older report versions — it reframes narrative into a register a PM can triage.

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

0. **Header table** — date, scope, author (with plugin version), generation method
0. **Method & Limitations** *(new in v0.3)* — mandatory block between Context and §1. States what the report is / is not, defines confidence levels (Verified / Likely / Inferred), reports dynamic-validation status, and reprints the grade rubric inline.
1. **Summary Stats** — LOC, comment LOC, test LOC, test/code ratio, test-suite run (new), test coverage, commits in last 90 days, active contributors, primary languages
2. **Executive Summary** — grade table across all 17 dimensions, plus a 3-4 sentence "bottom line"
3. **What the app does — Operational Picture** — numbered data-flow walkthrough, including a "Disaster Recovery & Backups" subsection
4. **Code Quality Findings** — one subsection per dimension with concrete evidence
5. **Findings Register** *(new in v0.3)* — consolidated table with ID × Dimension × Finding × Severity × Confidence × Evidence × Effort. 10–25 rows.
6. **Substantial Problems Worth Addressing** — concrete, numbered, with effort estimates. Every Critical and High row in §5 reappears here.
7. **What's Notably Good** — patterns worth keeping, reusing, copying to other projects
8. **Recommended Actions** — Immediate / Short term / Medium term buckets. Always include "Dependency Updates (Dependabot/Renovate)" in at least the short/medium term if not already in place.
9. **Bottom Line** — one-paragraph verdict

## Writing style

- Concrete > generic. "All six repositories import from `app/repositories/query_utils.py:12`" beats "shared filter utilities are used consistently".
- Cite file:line for every non-trivial finding. `auth.py:85-96` is precise enough to verify.
- Prefer quantified claims: "11 `capture_exception()` sites across 8,600 LOC", not "Sentry coverage is thin".
- Use m-dashes sparingly. Prefer commas, periods, or colons.
- Do not open with sycophancy. No "This is an impressive codebase!" — get to the substance.
- Flag uncertainty with one of three standard phrasings, matching the confidence levels in the Method & Limitations block and the §5 Findings Register:
  - **Verified** (default) — no prefix needed, just cite `file:line`.
  - **Likely** (spot-checked, one of many, strongly implied) — prefix with "Spot-checked:" or "Based on {N} sampled files of {M}:".
  - **Inferred** (absence of evidence, grep returned nothing, config-derived) — prefix with "Inferred from {what}:" or "Not directly verified — {reason}.".
  Use these three tags consistently. The Findings Register (§5) carries the machine-readable Confidence column; §4 prose uses the phrasings so narrative and register agree.
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