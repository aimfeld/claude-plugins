# Changelog

All notable changes to the `codebase-audit` plugin are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [0.2.0] — 2026-04-17

### Added
- **Dimension 17 — Technical debt & legacy stack.** Grades language-runtime currency, framework major-version distance, legacy-technology exposure, and upstream maintenance status. ([#2](https://github.com/aimfeld/claude-plugins/pull/2))

### Changed
- **Database FK cascade check** now probes DB-level migrations (constraint DDL) before flagging ORM-level cascade gaps, reducing false positives on codebases where referential actions are defined in SQL rather than the ORM. ([#1](https://github.com/aimfeld/claude-plugins/pull/1))
- **GDPR data-erasure guidance** refined to give the report a clearer stance on acceptable erasure designs. ([#1](https://github.com/aimfeld/claude-plugins/pull/1))

## [0.1.0]

### Added
- Initial release: 16-dimension quality assessment skill with evidence-based grading and `file:line` citations.

[0.2.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.2.0
[0.1.0]: https://github.com/aimfeld/claude-plugins/releases/tag/codebase-audit-v0.1.0
