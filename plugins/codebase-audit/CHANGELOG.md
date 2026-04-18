# Changelog

All notable changes to the `codebase-audit` plugin are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [0.3.0] — 2026-04-18

### Added
- **Method & Limitations block** (mandatory, between Context and §1 Summary Stats) stating what the report is and is not, defining three confidence levels (Verified / Likely / Inferred), reporting dynamic-validation status, and surfacing the grade rubric inline so readers see it before the grade table. Closes the "is this an audit?" question both external reviewers opened with. ([#TBD](https://github.com/aimfeld/claude-plugins/pulls))
- **§5 Findings Register** — a consolidated table with columns `ID × Dimension × Finding × Severity × Confidence × Evidence × Effort`. Turns narrative §4 findings into a register a reviewer or PM can triage without reading the full report. Every Critical/High row must reappear in §6 Substantial Problems. ([#TBD](https://github.com/aimfeld/claude-plugins/pulls))
- **Plugin version in Author field** — the Author row in the header table now carries the plugin version (e.g. `Claude (Opus 4.7) via the codebase-audit:report skill (v0.3.0)`) read from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Every saved report is self-identifying. ([#TBD](https://github.com/aimfeld/claude-plugins/pulls))
- **Optional Step 2b: test-suite execution with coverage.** When `collect_stats.sh` detects an installed test runner, the skill asks the user whether to run the suite (default skip). On confirmation it runs with a 5-minute timeout, requires the working tree to stay clean, and writes pass/fail + coverage into the Summary Stats and Method & Limitations block. Never installs dependencies; never modifies the target repo. ([#TBD](https://github.com/aimfeld/claude-plugins/pulls))
- **Test-runner detection in `collect_stats.sh`** (detect-only; no execution) covering PHPUnit/Pest, pytest, npm/yarn/pnpm test scripts, `go test`, `cargo test`, RSpec/minitest, and Maven/Gradle. Reports per-runner whether dependencies appear installed so Step 2b can skip cleanly when they are not. ([#TBD](https://github.com/aimfeld/claude-plugins/pulls))
- **Three-phrasing confidence convention for §4 prose** (Verified / Likely / Inferred) aligned with the Findings Register Confidence column so narrative and register agree. ([#TBD](https://github.com/aimfeld/claude-plugins/pulls))

### Changed
- **Report section numbering renumbered** to accommodate the new §5 Findings Register. What was §5 Substantial Problems is now §6; §6 Notably Good → §7; §7 Recommended Actions → §8; §8 Bottom Line → §9. Older archived reports keep their original numbering; new reports use the v0.3 layout. ([#TBD](https://github.com/aimfeld/claude-plugins/pulls))
- **Summary Stats table** adds a "Test suite run" row alongside the existing "Test coverage" row so dynamic-validation results surface next to the static LOC/coverage metrics. ([#TBD](https://github.com/aimfeld/claude-plugins/pulls))

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

[0.3.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.3.0
[0.2.1]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.2.1
[0.2.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.2.0
[0.1.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.1.0
