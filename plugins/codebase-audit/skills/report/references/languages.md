# Per-Language Reference

Read only the sections for languages actually present in the repo. Each section lists the idiomatic tools, config files, and what "good" looks like in that ecosystem.

If a language is absent from this file, fall back to general principles from `dimensions.md` and say so in the report ("spot-checked using general practices, not language-specific conventions").

**Cross-language IDE-adjacent signals (always probe):**
- `.editorconfig` — style baseline enforced by most editors (indent, final newline, trim trailing whitespace). Presence is a low-bar positive; absence on a multi-contributor repo is a mild smell.
- `.idea/inspectionProfiles/*.xml` — JetBrains (PhpStorm / WebStorm / IntelliJ / PyCharm / GoLand / RubyMine / Rider) project-committed inspection profile. When present, **open the XML and enumerate which `<inspection_tool>` entries are `enabled="true"` vs `enabled="false"`**. This is the team's de facto quality gate if CI is absent; the set of enabled inspections is the signal, not the mere existence of the file.
- `.vscode/settings.json` + `.vscode/extensions.json` — committed VS Code project config. `settings.json` controls linter/formatter activation; `extensions.json` `recommendations` is a soft-hint to contributors.

Treat IDE-enforced rules as **weaker than CI-enforced rules** (see `dimensions.md` §6): they depend on every contributor using that specific IDE, they run manually rather than on every PR, and they don't gate merges. Always report the IDE profile + the CI absence as distinct findings — credit dev-time enforcement, but still flag the missing CI gate.

---

## Python

**Manifests:** `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.py`, `setup.cfg`
**Lockfiles:** `uv.lock`, `poetry.lock`, `Pipfile.lock`, `requirements.txt` with hashes
**Virtualenv managers:** `uv`, `poetry`, `pipenv`, `hatch`, `rye`, `pip`

**What "good" looks like:**
- Dependencies managed with `uv` or `poetry`, lockfile committed.
- Type checker in CI: `mypy`, `pyright`, `pyre`, or `ty`. Zero errors gating merges.
- Linter: `ruff` or `flake8` + `black`. `ruff` preferred (fast, all-in-one).
- Test framework: `pytest`. `pytest-cov` for coverage. `pytest-xdist` for parallelization.
- Dependency audit: `pip-audit` in CI.

**Probes:**
- `grep -r "from __future__" --include="*.py"` — legacy Python 2/3 compat.
- Type hints: look at function signatures. Untyped public APIs are a smell.
- Raw SQL: `grep -rn "execute(" --include="*.py" | grep -iE 'f".*select|f".*insert|f".*update|f".*delete'` — f-string into SQL = injection risk.
- Async: `grep -rn "def " --include="*.py" | wc -l` vs `grep -rn "async def" --include="*.py" | wc -l`. If mostly async, check for blocking calls: `grep -rn "requests\.\|time\.sleep\|open(" --include="*.py"` in async functions.
- `asyncio.gather` on the same session/connection is a footgun — grep for `asyncio.gather` and spot-check the scope.
- Pydantic vs dataclasses: Pydantic for I/O boundary, dataclasses/TypedDict for internal shapes.

**IDE-level enforcement (probe these):**
- `.vscode/settings.json` — `python.analysis.typeCheckingMode` (Pylance), `python.linting.mypyEnabled`, `python.linting.ruffEnabled`, `python.formatting.provider`.
- `.idea/inspectionProfiles/*.xml` (PyCharm) — look for `PyPep8Inspection`, `PyTypeCheckerInspection`, `PyUnresolvedReferencesInspection`, `PyMypyInspection`, and whether they are `enabled="true"`. Cross-reference with `mypy.ini` / `pyproject.toml` `[tool.mypy]` / `[tool.ruff]` — a config that exists on disk but isn't activated anywhere (IDE or CI) is "configured but dead."

**Frameworks-specific:**
- **FastAPI:** Look for `APIRouter` prefix discipline (routers own `prefix=` not path). `Depends(current_active_user)` uniformly applied. `BaseModel` for every request/response shape.
- **Django:** `DEBUG = False` in prod settings. `ALLOWED_HOSTS` set. `SECURE_SSL_REDIRECT`, `SESSION_COOKIE_SECURE`. `django-debug-toolbar` not in prod deps.
- **Flask:** Blueprints used for modularity. `Flask-SQLAlchemy` with explicit session management.
- **Celery / RQ / Arq:** Retry config, idempotency keys, DLQ pattern.

**Coverage artifact paths:** `.coverage`, `coverage.xml`, `htmlcov/index.html`, `coverage.json`

---

## JavaScript / TypeScript

**Manifests:** `package.json`
**Lockfiles:** `package-lock.json` (npm), `yarn.lock`, `pnpm-lock.yaml`, `bun.lockb`

**What "good" looks like:**
- TypeScript with `strict: true` and `noUncheckedIndexedAccess: true`.
- Test framework: `vitest`, `jest`, `mocha`. `vitest` preferred for Vite projects.
- Linter: `eslint` + `prettier` OR the new `biome`.
- Dead-export detection: `knip` or `ts-unused-exports`.
- Dependency audit: `npm audit --audit-level=high` in CI.

**Probes:**
- `tsconfig.json`: check `strict`, `noUncheckedIndexedAccess`, `noImplicitReturns`, `exactOptionalPropertyTypes`.
- `any` density: `grep -rn ": any\|as any" src/ | wc -l` relative to total TS LOC.
- `@ts-ignore` / `@ts-expect-error`: `grep -rn "@ts-ignore\|@ts-expect-error" src/`. Each needs a comment with rationale.
- Bundler: Vite, Webpack, esbuild, Rollup, Turbopack, Bun.
- Bundle analysis: `vite-bundle-visualizer`, `webpack-bundle-analyzer`, or just `ls -la dist/assets/` after `npm run build`.
- Code splitting: `grep -rn "React.lazy\|lazy(\|import(\"\|dynamic(" src/`.
- Heavy deps in initial bundle: check `package.json` for `recharts`, `chart.js`, `d3`, `three`, `react-pdf`, etc., then check whether they're imported from route-level entry points.
- **Build-time type-checking bypass:** in webpack configs, look for `transpileOnly: true` on `ts-loader`; in Vite, `esbuild`-based TS transforms also skip type-checking by default. If present and no `tsc --noEmit` runs in CI or as a pre-build step, TS errors are compiled into prod.

**IDE-level enforcement (probe these):**
- `.vscode/settings.json` — `typescript.validate.enable`, `eslint.enable`, `editor.codeActionsOnSave` (esp. `source.fixAll.eslint`), `typescript.tsdk` pin.
- `.vscode/extensions.json` — `recommendations` array nudges every contributor to install ESLint / Prettier / Biome. Soft hint, but committing it is meaningful signal.
- `.idea/inspectionProfiles/*.xml` (WebStorm / IntelliJ) — look for `Eslint`, `TsLint` (legacy), `JSUnresolvedReference`, `JSUnusedGlobalSymbols`, `TypeScriptValidateJSTypes`. Cross-reference with `.eslintrc*` / `eslint.config.js` / `biome.json`: a config present but neither activated in the IDE profile nor run in CI is "configured but dead."

**Frontend-specific:**
- **React:** Check for `useEffect` dependency arrays, key warnings, state management pattern (TanStack Query, Redux, Zustand, Context only).
- **Next.js:** SSR/SSG/ISR correctness, `revalidate` values, `next/image` used instead of raw `<img>`.
- **Vue:** `<script setup>` vs options API consistency.

**Coverage artifact paths:** `coverage/lcov.info`, `coverage/coverage-summary.json`, `coverage/coverage-final.json`

---

## Go

**Manifests:** `go.mod`
**Lockfiles:** `go.sum` (always tracked)

**What "good" looks like:**
- Modules enabled. `GOFLAGS=-mod=readonly` in CI.
- Lint: `golangci-lint` with a real config (not defaults).
- Test framework: `go test` with `-race -cover`.
- Vulnerability scan: `govulncheck` in CI.
- Error wrapping: `fmt.Errorf("...: %w", err)`, not string concat.

**Probes:**
- Error handling: grep for `if err != nil` density. Ignored errors (`_ = doThing()`) should be rare and justified.
- Raw SQL: `database/sql` with parameterized queries. Grep for string concat into `.Query(` / `.Exec(`.
- Context propagation: public functions take `ctx context.Context` as first arg.
- Goroutines: check for missing `sync.WaitGroup` / errgroup; goroutines without termination paths.
- Race testing: is `-race` enabled in CI tests?
- Mutex vs channel discipline.

**IDE-level enforcement (probe these):**
- `.vscode/settings.json` — `go.lintTool` (`golangci-lint` / `staticcheck` / `revive`), `go.vetOnSave`, `go.formatTool` (`gofumpt` / `goimports`).
- `.idea/inspectionProfiles/*.xml` (GoLand) — `GoUnusedImportInspection`, `GoErrorMisuse`, `GoLinter` (wires golangci-lint). Cross-reference `.golangci.yml` / `.golangci.yaml`: if present but neither IDE nor CI activates it, "configured but dead."

**Coverage artifact paths:** `coverage.out`, `coverage.html`

---

## Rust

**Manifests:** `Cargo.toml`
**Lockfiles:** `Cargo.lock` (always tracked for binaries, sometimes for libraries)

**What "good" looks like:**
- `cargo clippy` with warnings as errors.
- `cargo audit` in CI.
- `#[deny(clippy::unwrap_used)]` or equivalent in non-test code.
- Error types via `thiserror` (library) or `anyhow` (application).

**Probes:**
- `unwrap()` / `expect()` density outside tests: `grep -rn "\.unwrap()\|\.expect(" src/ | grep -v test`.
- `unsafe` blocks: grep count; every one should have a comment justifying soundness.
- Async runtime: `tokio` / `async-std` / `smol` — and consistency.

**Coverage artifact paths:** `tarpaulin-report.html`, `lcov.info` from `cargo-llvm-cov`

---

## Java / Kotlin

**Manifests:** `pom.xml` (Maven), `build.gradle` / `build.gradle.kts` (Gradle)
**Lockfiles:** None standard; `dependency-locking` plugin for Gradle.

**What "good" looks like:**
- Build tool pinned (Maven wrapper `mvnw`, Gradle wrapper `gradlew` — both committed).
- Static analysis: `SpotBugs`, `PMD`, `Checkstyle`, `detekt` (Kotlin).
- Test: JUnit 5. `Testcontainers` for real-DB tests.
- Dependency audit: `org.owasp.dependencycheck` or Snyk.

**Probes:**
- Spring Boot: `@Transactional` discipline, `@ControllerAdvice` for global error handling, actuator endpoints exposed vs not.
- Raw JDBC: grep for string concat into `PreparedStatement`. Should be `?` placeholders.
- `@Autowired` field injection vs constructor injection (constructor is idiomatic modern Spring).

**IDE-level enforcement (probe these):**
- `.idea/inspectionProfiles/*.xml` (IntelliJ IDEA) — `SpotBugs`, `CheckStyle-IDEA`, `Qodana`, `NullableProblems`, `unused`. Kotlin: `detekt`. Cross-reference with `checkstyle.xml`, `spotbugs-exclude.xml`, `detekt.yml` — config present but not activated anywhere is "configured but dead."
- `.editorconfig` — often carries `dotnet_diagnostic.*` (shared convention with .NET) in JVM monorepos.

**Coverage artifact paths:** `target/site/jacoco/index.html`, `build/reports/jacoco/`

---

## Ruby

**Manifests:** `Gemfile`
**Lockfiles:** `Gemfile.lock`

**What "good" looks like:**
- `bundler-audit` in CI.
- `rubocop` + a real `.rubocop.yml`.
- Rails apps: `brakeman` for security static analysis.
- Test: RSpec or Minitest.

**Probes:**
- Rails: Strong Parameters everywhere, `find_by_sql` audits, N+1 detection via `bullet` gem.
- Raw SQL injection: grep for string interpolation in `.where(` / `.find_by_sql`.

**IDE-level enforcement (probe these):**
- `.vscode/settings.json` — `ruby.useLanguageServer`, `ruby.lint` (rubocop / standard / reek).
- `.idea/inspectionProfiles/*.xml` (RubyMine) — `RubyResolve`, `RubyArgCount`, `RubyLiteralArrayInspection`, `RubocopInspection`. Cross-reference with `.rubocop.yml` and Brakeman config — if present but only IDE-enforced, flag that CI doesn't run them.

**Coverage artifact paths:** `coverage/.last_run.json`, `coverage/index.html`

---

## PHP

**Manifests:** `composer.json`
**Lockfiles:** `composer.lock`

**What "good" looks like:**
- PHPStan / Psalm with level 6+.
- PHP-CS-Fixer or PHP_CodeSniffer.
- Tests: PHPUnit.
- Laravel: policies for authorization, Form Requests for validation.
- Symfony: voters for authorization.

**Probes:**
- Raw SQL injection: `mysqli_query` with concat. PDO with prepared statements is idiomatic.
- Laravel: mass assignment (`$fillable`), eager-loading (`->with()`) to avoid N+1.
- **Doctrine schema enforcement (read alongside dimensions §8):** Doctrine has two distinct "cascade" concepts. Do not conflate them:
  - `@ORM\JoinColumn(onDelete="CASCADE")` — emits a DB-level `ON DELETE CASCADE` when schema is generated from annotations via `doctrine:schema:update`. Enforced by the DB.
  - `cascade={"remove"}` on the association — ORM-level; runs only when `EntityManager::remove()` is called. Bypassed by raw SQL, DQL `DELETE`, and bulk updates.
  - **Many Doctrine projects use phinx / Doctrine Migrations with hand-written migration code as the source of schema truth**, and deliberately omit `onDelete` from the `@ORM\JoinColumn` annotations because the migration file already defines the FK with `ON DELETE CASCADE` at the DB level. In those projects, flagging absent `@ORM\JoinColumn(onDelete=...)` as a schema gap is a false positive — the integrity constraint lives in the migration, which is stronger.
  - **Probe order:** first grep the migrations directory (`migrations/`, `db/migrate/`, `src/Migrations/`) for `ON DELETE`, `addForeignKey`, `->foreignKey(`, `CONSTRAINT ... FOREIGN KEY ... ON DELETE`. Only then check `@ORM\JoinColumn` / `#[ORM\JoinColumn]`. Report based on the stronger of the two.
- **Laminas/Symfony/Laravel migration file globs:** phinx → `db/migrations/*.php` with `up()`/`change()`; Doctrine Migrations → `src/Migrations/Version*.php` with `up(Schema $schema)`; Laravel → `database/migrations/*.php` with `Schema::table(...)->foreign(...)->onDelete('cascade')`.

**IDE-level enforcement (probe these — matters a lot in PHP shops, where PhpStorm-centric teams often skip CI):**
- `.idea/inspectionProfiles/*.xml` (PhpStorm) — the single most important file to read when CI is absent or thin. Enumerate `<inspection_tool>` entries with `enabled="true"` and classify what's active. Common external-tool integrations and what their enabled state means:
  - `PhpCSValidationInspection` — wires PHP_CodeSniffer into the editor. Still depends on `phpcs.xml` / `.phpcs.xml.dist` existing.
  - `PhpCSFixerValidationInspection` — wires PHP-CS-Fixer; depends on `.php-cs-fixer.dist.php`.
  - `MessDetectorValidationInspection` — wires PHPMD; depends on `phpmd.xml` or default rulesets (`CODESIZE`, `DESIGN`, `UNUSEDCODE`, `NAMING`, `CONTROVERSIAL` are PHPMD categories). Check which categories are toggled on inside the inspection options.
  - `PhpStanGlobal` — wires PHPStan. **Critical:** read the `config` option inside — it points at e.g. `$PROJECT_DIR$/phpstan.neon.dist`. Then check `enabled=` on the inspection_tool itself. If `enabled="false"` *and* the `phpstan.neon.dist` file exists on disk *and* no CI step runs `vendor/bin/phpstan`, this is the canonical "configured but dead" case — report it by name.
  - `PsalmGlobal` — same pattern as PhpStanGlobal but for Psalm (`psalm.xml`).
  - `SecurityAdvisoriesInspection` — PhpStorm's built-in check that flags listed dev-only packages if they end up in production `require` (rather than `require-dev`). The `<option name="optionConfiguration">` list is the team's curated dev-package blocklist; count it and quote a few examples in the report.
  - `ForgottenDebugOutputInspection` — flags `var_dump`, `print_r`, `error_log`, `phpinfo`, framework-specific debug helpers. When `level="ERROR"` and `enabled="true"`, this is a real quality gate against debug-print leaks.
  - `DuplicatedCode` — PhpStorm's own duplicate-fragment detector. Read `<language minSize="N" name="PHP" />` to see the threshold; `minSize=60` is a sane default.
  - `PhpFieldCanBePromotedInspection`, `PhpRedundantDocCommentInspection`, `PhpTraditionalSyntaxArrayLiteralInspection`, `PhpUnusedParameterInspection` — PhpStorm-native modernizations / cleanliness rules. Presence of enabled rules here signals a team that has consciously trimmed the default profile.
  - `TsLint` — TypeScript-side enforcement inside a PHP project (often a webpack-driven frontend).
- `.vscode/settings.json` — less common in PHP shops, but if present look for `intelephense.environment.phpVersion`, `phpsab.executablePathCS`, `phpstan.enabled`.
- **Reporting pattern for PHP IDE findings:** quote the profile file path + profile `myName` value, list the enabled external-tool wirings with their referenced config files, and for each one state its enforcement status: CI-enforced / IDE-enforced / configured-but-dead. Finish with: *"These inspections run at the IDE level only — they depend on contributors using PhpStorm, and none of them gate merges because no CI is present."* (Adjust the last clause if CI does exist.)

---

## C# / .NET

**Manifests:** `*.csproj`, `*.sln`, `Directory.Build.props`
**Lockfiles:** `packages.lock.json` (opt-in via `RestorePackagesWithLockFile`)

**What "good" looks like:**
- Nullable reference types enabled (`<Nullable>enable</Nullable>`).
- `dotnet format` in CI.
- Analyzers: `.NET analyzers`, `Roslynator`, `StyleCop`.
- Tests: xUnit + `WebApplicationFactory` for integration tests.

**IDE-level enforcement (probe these):**
- `.editorconfig` — the canonical .NET rule-severity surface. Grep for `dotnet_diagnostic.<ID>.severity` lines; those are per-analyzer overrides (e.g. `dotnet_diagnostic.CA1304.severity = warning`). Count how many rules are raised to `error` / `warning` vs suppressed.
- `Directory.Build.props` — `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`, `<EnforceCodeStyleInBuild>true</EnforceCodeStyleInBuild>` push analyzer findings into the build itself (weaker than CI but stronger than IDE-only).
- `.idea/.idea.<sln>/.idea/inspectionProfiles/*.xml` (JetBrains Rider) and `*.DotSettings` (ReSharper-compatible solution settings) — look for `InspectionSeverity` entries and which are raised to `ERROR`.

---

## Shell / Bash

**Manifests:** None; scripts live in `bin/`, `scripts/`, `.github/workflows/`.

**What "good" looks like:**
- `shellcheck` linter run on all scripts.
- `set -euo pipefail` at the top.
- Quoting discipline (`"$var"`, not `$var`).

**Probes:**
- Grep for `rm -rf` / `sudo rm` — any findings need scrutiny.
- `eval` usage — should be rare and justified.

---

## Terraform / IaC

**Manifests:** `*.tf`, `*.tfvars`, `terraform.tf.json`

**What "good" looks like:**
- `terraform fmt` + `tflint` + `tfsec` / `checkov` in CI.
- Remote state in S3/GCS with DynamoDB locking.
- No secrets in `.tfvars` committed.

---

## Docker

**Probes:**
- `FROM` pinning: `python:3.13-slim` (OK), `@sha256:...` (better), `:latest` (bad).
- Multi-stage builds: reduces final image size.
- Non-root `USER` directive.
- `HEALTHCHECK` instruction.
- `.dockerignore` present and excludes `.git`, `node_modules`, tests.
- `docker scout` / `trivy` / `grype` image scan in CI.

---

## Universal fallbacks

If the language isn't listed here:

- **Stats:** tokei / git ls-files + wc -l still work.
- **Security:** raw SQL / hardcoded secrets / weak hashing (`MD5`, `SHA1` for passwords) are universally bad. Grep for them.
- **Secrets:** `git grep -iE "(api_key|secret_key|password|token)\s*=\s*['\"]"` catches most.
- **Tests:** look for a `test/` or `tests/` directory; any framework's artifacts in CI.
- **CI:** `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `azure-pipelines.yml`, `.circleci/config.yml`, `bitbucket-pipelines.yml`.
