# Changelog

All notable changes to the `codebase-audit` plugin are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

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

[0.2.1]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.2.1
[0.2.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.2.0
[0.1.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.1.0
