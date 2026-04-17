# Per-Language Reference

Read only the sections for languages actually present in the repo. Each section lists the idiomatic tools, config files, and what "good" looks like in that ecosystem.

If a language is absent from this file, fall back to general principles from `dimensions.md` and say so in the report ("spot-checked using general practices, not language-specific conventions").

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

---

## C# / .NET

**Manifests:** `*.csproj`, `*.sln`, `Directory.Build.props`
**Lockfiles:** `packages.lock.json` (opt-in via `RestorePackagesWithLockFile`)

**What "good" looks like:**
- Nullable reference types enabled (`<Nullable>enable</Nullable>`).
- `dotnet format` in CI.
- Analyzers: `.NET analyzers`, `Roslynator`, `StyleCop`.
- Tests: xUnit + `WebApplicationFactory` for integration tests.

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
