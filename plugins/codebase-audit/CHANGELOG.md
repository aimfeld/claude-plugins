# Changelog

All notable changes to the `codebase-audit` plugin are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [0.4.0] — 2026-04-18

### Added
- **Environment-tier verdict from `collect_stats.sh`.** The script now ends with a grep-able `ENVIRONMENT_TIER: warm|partial|cold` line plus per-signal flags (`SIGNAL_LOC_TOOL`, `SIGNAL_TEST_RUNNER_DETECTED`, `SIGNAL_TEST_DEPS_INSTALLED`) so the skill can tell whether the audit was run from a warm active-dev environment, a partially-equipped one, or a cold clone with no tooling — and branch accordingly. ([#8](https://github.com/aimfeld/claude-plugins/pull/8))
- **Single install-or-skip decision (Step 2b.1a in `SKILL.md`).** When the environment tier is `partial`, the skill asks *once* whether to install missing deps, run only what's already runnable, or skip Step 2b entirely — quoting commands from the repo's own docs (README, Makefile, package.json scripts) rather than guessing. Replaces what would previously have been N per-suite permission prompts. ([#8](https://github.com/aimfeld/claude-plugins/pull/8))
- **Section-level assessability vocabulary in the report template.** Method & Limitations block now distinguishes claim-level confidence (Verified / Likely / Inferred, unchanged) from section-level assessability (`Measured` / `Inferred from artifacts` / `Not assessable without setup`). Cold-clone reports degrade explicitly — §1 rows state what tooling would be needed to upgrade the row to Measured, and §5 caps the confidence of findings sourced from Not-assessable sections at Inferred. ([#8](https://github.com/aimfeld/claude-plugins/pull/8))

### Fixed
- **`collect_stats.sh` portability.** Added a bash 4+ version guard (fails loudly with a macOS-specific `brew install bash` hint instead of emitting a cryptic syntax error under bash 3.2). Output path now respects `$TMPDIR` for sandboxed/containerized environments. ([#8](https://github.com/aimfeld/claude-plugins/pull/8))
- **`collect_stats.sh` backup-evidence grep.** Replaced the GNU-only `grep -rlI --exclude-dir=…` with a portable `find -prune … -print0 | xargs -0 grep -lEi` pipeline that works across GNU grep, BSD grep (macOS), and busybox. ([#8](https://github.com/aimfeld/claude-plugins/pull/8))
- **`collect_stats.sh` test-LOC word-splitting.** Rewrote `for d in $(… | sort -u)` as `while IFS= read -r d; do …; done < <(…)` so test-directory paths containing spaces are counted correctly instead of silently skipped. ([#8](https://github.com/aimfeld/claude-plugins/pull/8))
- **`collect_stats.sh` `gh run list` error masking.** Routed the `gh run list` call through a temp file and inspected its exit code via `PIPESTATUS`-equivalent pattern — previously `tee` masked `gh` failures behind its own success, silently producing an empty "no recent runs" result rather than telling the reader `gh` couldn't ask. ([#8](https://github.com/aimfeld/claude-plugins/pull/8))

## [0.3.0] — 2026-04-18

### Added
- **Method & Limitations block** (mandatory, between Context and §1 Summary Stats) stating what the report is and is not, defining three confidence levels (Verified / Likely / Inferred), reporting dynamic-validation status, and surfacing the grade rubric inline so readers see it before the grade table. Closes the "is this an audit?" question both external reviewers opened with. ([#7](https://github.com/aimfeld/claude-plugins/pull/7))
- **§5 Findings Register** — a consolidated table with columns `ID × Dimension × Finding × Severity × Confidence × Evidence × Effort`. Turns narrative §4 findings into a register a reviewer or PM can triage without reading the full report. Every Critical/High row must reappear in §6 Substantial Problems. ([#7](https://github.com/aimfeld/claude-plugins/pull/7))
- **Plugin version in Author field** — the Author row in the header table now carries the plugin version (e.g. `Claude (Opus 4.7) via the codebase-audit:report skill (v0.3.0)`) read from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Every saved report is self-identifying. ([#7](https://github.com/aimfeld/claude-plugins/pull/7))
- **Optional Step 2b: per-suite test execution with coverage.** Orchestration-based rather than rigid-command: the skill reads `collect_stats.sh` detection output + the project's README / Makefile / `package.json` scripts / `composer.json` scripts, proposes the exact documented commands to the user per suite (`AskUserQuestion`, one question per suite), and runs only what the user approves. Each suite gets its own row in §1 Summary Stats. Never invents commands, never installs dependencies, never modifies the target repo. 5-minute timeout per suite with pre/post `git status --porcelain` guard. ([#7](https://github.com/aimfeld/claude-plugins/pull/7))
- **Monorepo-aware test-runner detection in `collect_stats.sh`** (detect-only; no execution). Scans depth ≤3 for nested `package.json` test scripts, `phpunit.xml`, and `pyproject.toml` `[tool.pytest]`. Surfaces test-command hints (README "Running Tests" headings, `Makefile`/`justfile`/`Taskfile` test targets, `package.json`/`composer.json`/`pyproject.toml` script lines) so Step 2b can propose the project's documented commands instead of guessing. ([#7](https://github.com/aimfeld/claude-plugins/pull/7))
- **Three-phrasing confidence convention for §4 prose** (Verified / Likely / Inferred) aligned with the Findings Register Confidence column so narrative and register agree. ([#7](https://github.com/aimfeld/claude-plugins/pull/7))

### Changed
- **Report section numbering renumbered** to accommodate the new §5 Findings Register. What was §5 Substantial Problems is now §6; §6 Notably Good → §7; §7 Recommended Actions → §8; §8 Bottom Line → §9. Older archived reports keep their original numbering; new reports use the v0.3 layout. ([#7](https://github.com/aimfeld/claude-plugins/pull/7))
- **Summary Stats table** adds one "Test suite run — {suite}" row per suite (e.g. backend, frontend) with the exact command used + where it came from. The existing "Test coverage" row remains for single-suite projects or as an aggregate when one exists. ([#7](https://github.com/aimfeld/claude-plugins/pull/7))

## [0.2.1] — 2026-04-17

### Added
- **Dimension 6 now probes IDE-committed static analysis profiles** (`.idea/inspectionProfiles/*.xml`, `.vscode/settings.json`, `.vscode/extensions.json`, `.editorconfig`) as a weaker-but-real enforcement layer alongside CI gates. The probe reports which inspections are `enabled="true"`, which external tools they wire up (PHPStan, Psalm, PHP-CS, PHPMD, ESLint, mypy, rubocop, SpotBugs, .NET analyzers, etc.), and classifies each tool as **CI-enforced** / **IDE-enforced** / **configured-but-dead** — the last being the misleading state where a tool config exists on disk but neither CI nor the IDE profile activates it. ([#6](https://github.com/aimfeld/claude-plugins/pull/6))
- **Per-language IDE-enforcement probe bullets** in `references/languages.md` for Python (PyCharm / VS Code), JS/TS (WebStorm / VS Code, incl. webpack `transpileOnly`), Go (GoLand), Ruby (RubyMine), PHP (PhpStorm — expanded with inspection-class reference list including `PhpCSValidationInspection`, `MessDetectorValidationInspection`, `PhpStanGlobal`, `PsalmGlobal`, `SecurityAdvisoriesInspection`, `ForgottenDebugOutputInspection`, `DuplicatedCode`), Java/Kotlin (IntelliJ / detekt), and C#/.NET (`dotnet_diagnostic.*` severities, Rider / ReSharper `.DotSettings`). ([#6](https://github.com/aimfeld/claude-plugins/pull/6))
- **`collect_stats.sh` now surfaces IDE-profile artifacts** in its output so the assessor sees them without manual grepping. ([#6](https://github.com/aimfeld/claude-plugins/pull/6))

### Changed
- **Dimension 6 grading calibration:** IDE-only enforcement (no CI) is still a gap — it doesn't gate merges, runs manually rather than on every PR, and depends on every contributor using the same IDE. But it is now *credited* instead of silently missed. Reports should name the profile file, list its active inspections, and distinguish "IDE-enforced but not CI-enforced" from "no enforcement at all." ([#6](https://github.com/aimfeld/claude-plugins/pull/6))

## [0.2.0] — 2026-04-17

### Added
- **Dimension 17 — Technical debt & legacy stack.** Grades language-runtime currency, framework major-version distance, legacy-technology exposure, and upstream maintenance status. ([#2](https://github.com/aimfeld/claude-plugins/pull/2))

### Changed
- **Database FK cascade check** now probes DB-level migrations (constraint DDL) before flagging ORM-level cascade gaps, reducing false positives on codebases where referential actions are defined in SQL rather than the ORM. ([#1](https://github.com/aimfeld/claude-plugins/pull/1))
- **GDPR data-erasure guidance** refined to give the report a clearer stance on acceptable erasure designs. ([#1](https://github.com/aimfeld/claude-plugins/pull/1))

## [0.1.0]

### Added
- Initial release: 16-dimension quality assessment skill with evidence-based grading and `file:line` citations.

[0.4.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.4.0
[0.3.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.3.0
[0.2.1]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.2.1
[0.2.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.2.0
[0.1.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.1.0
