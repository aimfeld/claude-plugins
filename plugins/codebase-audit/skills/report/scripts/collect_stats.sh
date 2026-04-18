#!/usr/bin/env bash
# Collect summary stats for a git repo quality assessment.
#
# Usage:
#   collect_stats.sh <repo-path>
#
# Produces human-readable output to stdout and writes the same to
# ${TMPDIR:-/tmp}/quality-assessment-stats.txt for the caller to reference.
#
# Requires bash 4+. macOS ships with bash 3.2 as /bin/bash; the script
# aborts loudly with an install hint if run under anything older.
#
# Sections:
#   - Repo identity (name, branch, commit, remote)
#   - LOC breakdown (tokei -> scc -> cloc -> git+wc fallback)
#   - Test directory LOC (heuristic)
#   - Git activity (commits, contributors) for last 90 days
#   - Dependency manifests + lockfile presence
#   - Coverage artifact search
#   - Test runner detection + test-command hints (for Step 2b orchestration)
#   - CI workflow discovery + recent run timing (if gh is available)
#   - Docker / deploy artifacts
#   - Backup / restore evidence (grep only — does not assume tools)
#   - Environment tier verdict (warm / partial / cold) — tells the skill
#     whether dynamic validation (test execution) is viable and, if so,
#     whether to consolidate missing-deps questions into one prompt
#
# The script is read-only on the target repo. It does not run tests
# or install anything without asking.

set -uo pipefail

# Require bash 4+ (arrays with += append, `read -d ''`, nullglob used below).
# macOS ships with bash 3.2 as /bin/bash; `brew install bash` provides a newer one.
if ((${BASH_VERSINFO[0]:-0} < 4)); then
  echo "error: collect_stats.sh requires bash 4+ (detected ${BASH_VERSION:-unknown})." >&2
  echo "       On macOS, install with 'brew install bash' and re-run using" >&2
  echo "       /opt/homebrew/bin/bash (Apple Silicon) or /usr/local/bin/bash (Intel)." >&2
  exit 2
fi

REPO="${1:-}"
if [[ -z "${REPO}" ]]; then
  echo "usage: $0 <repo-path>" >&2
  exit 2
fi
if [[ ! -d "${REPO}" ]]; then
  echo "error: '${REPO}' is not a directory" >&2
  exit 2
fi
if [[ ! -d "${REPO}/.git" ]]; then
  echo "warning: '${REPO}' does not contain a .git directory — some stats will be missing" >&2
fi

OUT="${TMPDIR:-/tmp}/quality-assessment-stats.txt"
: > "${OUT}"

# Tier-tracking flags. See the "Environment tier" section at the end of the script
# for the final verdict. Signals are set as the respective sections run.
HAS_LOC_TOOL=0
TEST_RUNNER_DETECTED=0
TEST_DEPS_INSTALLED=0

log() {
  echo "$*" | tee -a "${OUT}"
}

section() {
  log ""
  log "=== $* ==="
}

# ----- Identity -----
section "Identity"
log "Path: ${REPO}"
if [[ -d "${REPO}/.git" ]]; then
  log "Branch: $(git -C "${REPO}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  log "Commit: $(git -C "${REPO}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  log "Remote: $(git -C "${REPO}" config --get remote.origin.url 2>/dev/null || echo '(no remote)')"
  FIRST_COMMIT=$({ git -C "${REPO}" log --reverse --format=%ai 2>/dev/null || true; } | head -n1)
  log "First commit: ${FIRST_COMMIT:-unknown}"
  log "Last commit:  $(git -C "${REPO}" log -1 --format=%ai 2>/dev/null || echo unknown)"
fi

# ----- LOC -----
section "LOC breakdown"

LOC_TOOL=""
if command -v tokei >/dev/null 2>&1; then
  LOC_TOOL="tokei"
elif command -v scc >/dev/null 2>&1; then
  LOC_TOOL="scc"
elif command -v cloc >/dev/null 2>&1; then
  LOC_TOOL="cloc"
fi
[[ -n "${LOC_TOOL}" ]] && HAS_LOC_TOOL=1

if [[ -z "${LOC_TOOL}" ]]; then
  log "tokei/scc/cloc not found on PATH."
  log ""
  log "For accurate LOC with code/comment/blank split, install tokei:"
  log "  Debian/Ubuntu: sudo apt install tokei"
  log "  macOS:        brew install tokei"
  log "  Any Rust env: cargo install tokei"
  log ""
  log "The skill-runner may prompt the user to install tokei. If declined,"
  log "stats below are ROUGH (git ls-files | wc -l of tracked files)."
  log ""
  log "=== Rough LOC (fallback) ==="
  if [[ -d "${REPO}/.git" ]]; then
    TOTAL_FILES=$(git -C "${REPO}" ls-files 2>/dev/null | wc -l)
    # git grep -c '' counts lines per tracked text file (skips binaries cleanly)
    TOTAL_LINES=$(git -C "${REPO}" grep --cached -I -c '' 2>/dev/null | awk -F: '{sum+=$NF} END {print sum+0}')
    log "Tracked files: ${TOTAL_FILES}"
    log "Total lines of tracked text files (incl. blanks/comments): ${TOTAL_LINES:-unknown}"
    log ""
    log "Per-extension rough breakdown — lines by extension, top 15:"
    git -C "${REPO}" grep --cached -I -c '' 2>/dev/null \
      | awk -F: '{
          n=split($1,parts,".");
          ext = (n>1) ? parts[n] : "(no-ext)";
          sum[ext] += $NF;
          files[ext] += 1;
        } END {
          for (e in sum) printf "  %8d lines  %5d files  .%s\n", sum[e], files[e], e;
        }' \
      | sort -rn | head -15 | tee -a "${OUT}"
  fi
else
  log "Using: ${LOC_TOOL}"
  case "${LOC_TOOL}" in
    tokei) tokei "${REPO}" 2>/dev/null | tee -a "${OUT}" ;;
    scc)   scc "${REPO}" 2>/dev/null | tee -a "${OUT}" ;;
    cloc)  cloc --quiet "${REPO}" 2>/dev/null | tee -a "${OUT}" ;;
  esac
fi

# ----- Test LOC heuristic -----
section "Test directory LOC (heuristic)"
TEST_DIRS=()
for d in tests test __tests__ spec specs; do
  if [[ -d "${REPO}/${d}" ]]; then
    TEST_DIRS+=("${d}")
  fi
done
# Nested test dirs (frontend/src/**/__tests__, backend/tests)
while IFS= read -r -d '' d; do
  rel="${d#${REPO}/}"
  # Avoid counting node_modules / .venv / build output
  case "${rel}" in
    */node_modules/*|*/.venv/*|*/dist/*|*/build/*|*/.git/*) continue ;;
  esac
  TEST_DIRS+=("${rel}")
done < <(find "${REPO}" -type d \( -name tests -o -name test -o -name __tests__ -o -name spec -o -name specs \) -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.git/*' -print0 2>/dev/null)

if [[ ${#TEST_DIRS[@]} -eq 0 ]]; then
  log "No test directories detected (tests/, test/, __tests__/, spec/)."
else
  log "Detected test directories:"
  # dedup
  printf '%s\n' "${TEST_DIRS[@]}" | sort -u | tee -a "${OUT}"
  log ""
  log "Test LOC by directory (counting .py .ts .tsx .js .jsx .go .rs .java .rb .php .cs files):"
  # `while read` instead of `for d in $(...)` so test-dir paths containing
  # spaces don't get word-split across iterations.
  while IFS= read -r d; do
    [[ -z "${d}" ]] && continue
    full="${REPO}/${d}"
    [[ ! -d "${full}" ]] && continue
    loc=$(find "${full}" -type f \( \
      -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
      -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.kt' \
      -o -name '*.rb' -o -name '*.php' -o -name '*.cs' \
      \) -not -path '*/node_modules/*' -not -path '*/.venv/*' -exec cat {} + 2>/dev/null | wc -l)
    files=$(find "${full}" -type f \( \
      -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
      -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.kt' \
      -o -name '*.rb' -o -name '*.php' -o -name '*.cs' \
      \) -not -path '*/node_modules/*' -not -path '*/.venv/*' | wc -l)
    printf '  %-50s %4d files / %6d LOC\n' "${d}" "${files}" "${loc}" | tee -a "${OUT}"
  done < <(printf '%s\n' "${TEST_DIRS[@]}" | sort -u)
fi

# ----- Git activity -----
section "Git activity (last 90 days)"
if [[ -d "${REPO}/.git" ]]; then
  SINCE="90 days ago"
  COMMITS_90=$(git -C "${REPO}" log --since="${SINCE}" --oneline 2>/dev/null | wc -l)
  CONTRIB_90=$(git -C "${REPO}" log --since="${SINCE}" --format='%ae' 2>/dev/null | sort -u | wc -l)
  log "Commits (last 90 days):      ${COMMITS_90}"
  log "Unique authors (last 90 days): ${CONTRIB_90}"
  log ""
  log "Top authors (last 90 days):"
  git -C "${REPO}" log --since="${SINCE}" --format='%an <%ae>' 2>/dev/null | sort | uniq -c | sort -rn | head -5 | tee -a "${OUT}"
  log ""
  TOTAL_COMMITS=$(git -C "${REPO}" rev-list --count HEAD 2>/dev/null || echo 0)
  log "Total commits on HEAD: ${TOTAL_COMMITS}"
fi

# ----- Dependency manifests + lockfiles -----
section "Dependency manifests & lockfiles"
for manifest in \
  pyproject.toml requirements.txt requirements-dev.txt Pipfile setup.py setup.cfg \
  package.json \
  go.mod \
  Cargo.toml \
  pom.xml build.gradle build.gradle.kts \
  Gemfile \
  composer.json \
  Dockerfile docker-compose.yml docker-compose.yaml docker-compose.dev.yml docker-compose.prod.yml
do
  if [[ -f "${REPO}/${manifest}" ]]; then
    log "  manifest: ${manifest}"
  fi
done

log ""
log "Lockfiles:"
for lock in \
  uv.lock poetry.lock Pipfile.lock \
  package-lock.json yarn.lock pnpm-lock.yaml bun.lockb \
  go.sum \
  Cargo.lock \
  Gemfile.lock \
  composer.lock
do
  if [[ -f "${REPO}/${lock}" ]]; then
    log "  lockfile: ${lock}"
  fi
done

# Any nested manifests (monorepo hint)
log ""
log "Nested package.json (depth <= 3, up to 20 paths):"
find "${REPO}" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null | head -20 | tee -a "${OUT}"

# ----- Coverage artifacts -----
section "Coverage artifact search (existing files only, no tests run)"
FOUND_COV=0
for art in \
  .coverage coverage.xml coverage.json \
  htmlcov/index.html \
  coverage/lcov.info coverage/coverage-summary.json coverage/coverage-final.json \
  coverage.out \
  tarpaulin-report.html \
  target/site/jacoco/index.html build/reports/jacoco/test/html/index.html
do
  if [[ -e "${REPO}/${art}" ]]; then
    log "  found: ${art}"
    FOUND_COV=1
  fi
done
if [[ ${FOUND_COV} -eq 0 ]]; then
  log "  (none found — coverage not measured locally; report as 'Not measured')"
fi

# ----- Test runner detection -----
section "Test runner detection (for optional Step 2b — no tests are executed here)"
TEST_RUNNER_FOUND=0

# PHP — PHPUnit / Pest (config can be at root or in tests/)
PHPUNIT_CONFIG=""
for cfg in phpunit.xml phpunit.xml.dist tests/phpunit.xml tests/phpunit.xml.dist; do
  if [[ -f "${REPO}/${cfg}" ]]; then
    PHPUNIT_CONFIG="${cfg}"
    break
  fi
done
if [[ -n "${PHPUNIT_CONFIG}" ]]; then
  if [[ -x "${REPO}/vendor/bin/phpunit" ]]; then
    log "  php: ${PHPUNIT_CONFIG} + vendor/bin/phpunit present (deps installed)"
    TEST_DEPS_INSTALLED=1
  elif [[ -x "${REPO}/vendor/bin/pest" ]]; then
    log "  php: ${PHPUNIT_CONFIG} + vendor/bin/pest present (deps installed)"
    TEST_DEPS_INSTALLED=1
  else
    log "  php: ${PHPUNIT_CONFIG} present, but vendor/ missing — deps not installed (skip Step 2b)"
  fi
  TEST_RUNNER_FOUND=1
fi

# Python — pytest / unittest
if [[ -f "${REPO}/pytest.ini" || -f "${REPO}/tox.ini" ]] || grep -q '\[tool\.pytest' "${REPO}/pyproject.toml" 2>/dev/null; then
  PYTEST_BIN=""
  [[ -x "${REPO}/.venv/bin/pytest" ]] && PYTEST_BIN="${REPO}/.venv/bin/pytest"
  [[ -z "${PYTEST_BIN}" && -x "${REPO}/venv/bin/pytest" ]] && PYTEST_BIN="${REPO}/venv/bin/pytest"
  [[ -z "${PYTEST_BIN}" ]] && command -v pytest >/dev/null 2>&1 && PYTEST_BIN="$(command -v pytest)"
  if [[ -n "${PYTEST_BIN}" ]]; then
    log "  python: pytest config + runner at ${PYTEST_BIN} (deps likely installed)"
    TEST_DEPS_INSTALLED=1
  else
    log "  python: pytest config present, but pytest binary not found in .venv/venv/PATH (skip Step 2b)"
  fi
  TEST_RUNNER_FOUND=1
fi

# JavaScript / TypeScript — npm/yarn/pnpm test script
if [[ -f "${REPO}/package.json" ]]; then
  TEST_SCRIPT=$(grep -oE '"test"\s*:\s*"[^"]+"' "${REPO}/package.json" 2>/dev/null | head -1)
  if [[ -n "${TEST_SCRIPT}" ]]; then
    if [[ -d "${REPO}/node_modules" ]]; then
      log "  js/ts: package.json ${TEST_SCRIPT} + node_modules/ present (deps installed)"
      TEST_DEPS_INSTALLED=1
    else
      log "  js/ts: package.json ${TEST_SCRIPT} present, but node_modules/ missing (skip Step 2b)"
    fi
    TEST_RUNNER_FOUND=1
  fi
fi

# Go — any *_test.go file
if [[ -f "${REPO}/go.mod" ]]; then
  GO_TEST_COUNT=$(find "${REPO}" -name '*_test.go' -not -path '*/vendor/*' -not -path '*/.git/*' 2>/dev/null | head -50 | wc -l)
  if [[ "${GO_TEST_COUNT}" -gt 0 ]]; then
    log "  go: go.mod + ${GO_TEST_COUNT}+ *_test.go files (go test always works, deps auto-resolved)"
    TEST_RUNNER_FOUND=1
    command -v go >/dev/null 2>&1 && TEST_DEPS_INSTALLED=1
  fi
fi

# Rust — Cargo.toml + tests/ or *#[cfg(test)]*
if [[ -f "${REPO}/Cargo.toml" ]]; then
  if [[ -d "${REPO}/tests" ]] || grep -rq '#\[cfg(test)\]' "${REPO}/src" 2>/dev/null; then
    log "  rust: Cargo.toml + test modules present (cargo test handles deps)"
    TEST_RUNNER_FOUND=1
    command -v cargo >/dev/null 2>&1 && TEST_DEPS_INSTALLED=1
  fi
fi

# Ruby — Gemfile + spec/ or test/
if [[ -f "${REPO}/Gemfile" ]]; then
  if [[ -d "${REPO}/spec" || -d "${REPO}/test" ]]; then
    if [[ -f "${REPO}/Gemfile.lock" ]]; then
      log "  ruby: Gemfile + $(ls -d "${REPO}"/spec "${REPO}"/test 2>/dev/null | tr '\n' ' ')present (deps likely installed)"
      TEST_DEPS_INSTALLED=1
    else
      log "  ruby: Gemfile + spec/test dir present, but no Gemfile.lock — run bundle install first"
    fi
    TEST_RUNNER_FOUND=1
  fi
fi

# Java — Maven / Gradle with src/test/java/
if [[ -d "${REPO}/src/test/java" ]]; then
  if [[ -f "${REPO}/pom.xml" ]]; then
    log "  java: pom.xml + src/test/java/ present (mvn test — requires Maven on PATH)"
    TEST_RUNNER_FOUND=1
    command -v mvn >/dev/null 2>&1 && TEST_DEPS_INSTALLED=1
  elif [[ -f "${REPO}/build.gradle" || -f "${REPO}/build.gradle.kts" ]]; then
    log "  java: build.gradle + src/test/java/ present (gradle test — requires Gradle on PATH)"
    TEST_RUNNER_FOUND=1
    { command -v gradle >/dev/null 2>&1 || [[ -x "${REPO}/gradlew" ]]; } && TEST_DEPS_INSTALLED=1
  fi
fi

if [[ "${TEST_RUNNER_FOUND}" = "0" ]]; then
  log "  (no recognized root-level test runner configuration detected)"
fi

# Monorepo / subdirectory scan — common on projects with separate frontend + backend
log ""
log "Subdirectory scan (depth ≤3, excluding node_modules/.venv/vendor/dist/build):"
MONO_HITS=0

# Nested package.json with a "test" script — catches React/Vue/Svelte subdirs like frontend/, web/, apps/*, packages/*
while IFS= read -r pkg; do
  [[ -z "${pkg}" ]] && continue
  rel="${pkg#${REPO}/}"
  [[ "${rel}" = "package.json" ]] && continue
  TEST_SCRIPT=$(grep -oE '"test"\s*:\s*"[^"]+"' "${pkg}" 2>/dev/null | head -1)
  if [[ -n "${TEST_SCRIPT}" ]]; then
    dir="$(dirname "${rel}")"
    if [[ -d "${REPO}/${dir}/node_modules" ]]; then
      log "  js/ts: ${rel} ${TEST_SCRIPT} + ${dir}/node_modules/ present (deps installed)"
      TEST_DEPS_INSTALLED=1
    else
      log "  js/ts: ${rel} ${TEST_SCRIPT} present, but ${dir}/node_modules/ missing"
    fi
    MONO_HITS=$((MONO_HITS + 1))
  fi
done < <(find "${REPO}" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null)

# Nested phpunit.xml beyond root + tests/ (e.g., packages/X/phpunit.xml)
while IFS= read -r cfg; do
  [[ -z "${cfg}" ]] && continue
  rel="${cfg#${REPO}/}"
  case "${rel}" in
    phpunit.xml|phpunit.xml.dist|tests/phpunit.xml|tests/phpunit.xml.dist) continue ;;
  esac
  dir="$(dirname "${rel}")"
  if [[ -d "${REPO}/${dir}/vendor" ]]; then
    log "  php: ${rel} + ${dir}/vendor/ present (deps installed)"
    TEST_DEPS_INSTALLED=1
  else
    log "  php: ${rel} present (vendor status unknown)"
  fi
  MONO_HITS=$((MONO_HITS + 1))
done < <(find "${REPO}" -maxdepth 3 \( -name phpunit.xml -o -name phpunit.xml.dist \) -not -path '*/vendor/*' 2>/dev/null)

# Nested pyproject.toml with [tool.pytest] beyond root
while IFS= read -r pyproj; do
  [[ -z "${pyproj}" ]] && continue
  rel="${pyproj#${REPO}/}"
  [[ "${rel}" = "pyproject.toml" ]] && continue
  if grep -q '\[tool\.pytest' "${pyproj}" 2>/dev/null; then
    log "  python: ${rel} has [tool.pytest] (nested project)"
    MONO_HITS=$((MONO_HITS + 1))
  fi
done < <(find "${REPO}" -maxdepth 3 -name pyproject.toml -not -path '*/.venv/*' 2>/dev/null)

if [[ "${MONO_HITS}" = "0" ]]; then
  log "  (no nested test configs found — project is single-module)"
fi

# ----- Test-command hints (for Claude to read when proposing commands in Step 2b) -----
section "Test-command hints (for Step 2b orchestration — do NOT execute from this script)"

# README sections mentioning test/testing/running-tests
if [[ -f "${REPO}/README.md" ]]; then
  README_TEST_LINES=$(grep -niE '^#+ *(running tests|testing|tests?|test coverage)' "${REPO}/README.md" 2>/dev/null | head -5)
  if [[ -n "${README_TEST_LINES}" ]]; then
    log "README.md test-related headings (Claude should read these lines for exact commands):"
    echo "${README_TEST_LINES}" | sed 's/^/  /' | tee -a "${OUT}"
  else
    log "README.md: no explicit 'Running Tests' / 'Testing' section found"
  fi
fi

# Makefile / justfile / Taskfile targets
for taskfile in Makefile makefile justfile Taskfile.yml Taskfile.yaml; do
  if [[ -f "${REPO}/${taskfile}" ]]; then
    HITS=$(grep -niE '^(test|cover|coverage|check)[^:]*:' "${REPO}/${taskfile}" 2>/dev/null | head -10)
    if [[ -n "${HITS}" ]]; then
      log "${taskfile} test-like targets:"
      echo "${HITS}" | sed 's/^/  /' | tee -a "${OUT}"
    fi
  fi
done

# pyproject.toml scripts ([tool.poe.tasks], [project.scripts])
if [[ -f "${REPO}/pyproject.toml" ]]; then
  POE_HITS=$(grep -niE '^(test|cov|coverage|check|ci) *=' "${REPO}/pyproject.toml" 2>/dev/null | head -10)
  if [[ -n "${POE_HITS}" ]]; then
    log "pyproject.toml script-like lines:"
    echo "${POE_HITS}" | sed 's/^/  /' | tee -a "${OUT}"
  fi
fi

# package.json scripts — root and nested
while IFS= read -r pkg; do
  [[ -z "${pkg}" ]] && continue
  rel="${pkg#${REPO}/}"
  # Extract script keys that look test-related (test, test:*, coverage, cov, ci, check)
  SCRIPT_HITS=$(grep -oE '"(test|test:[a-z0-9_-]+|coverage|cov|ci|check|lint)"\s*:\s*"[^"]+"' "${pkg}" 2>/dev/null | head -15)
  if [[ -n "${SCRIPT_HITS}" ]]; then
    log "${rel} test-like scripts:"
    echo "${SCRIPT_HITS}" | sed 's/^/  /' | tee -a "${OUT}"
  fi
done < <(find "${REPO}" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null)

# composer.json scripts
if [[ -f "${REPO}/composer.json" ]]; then
  COMP_HITS=$(grep -oE '"(test|tests|coverage|check|ci|lint)"\s*:\s*"[^"]+"' "${REPO}/composer.json" 2>/dev/null | head -10)
  if [[ -n "${COMP_HITS}" ]]; then
    log "composer.json test-like scripts:"
    echo "${COMP_HITS}" | sed 's/^/  /' | tee -a "${OUT}"
  fi
fi

log ""
log "(Claude: read the surfaced README sections, Makefile/Taskfile targets, and package.json scripts"
log " before proposing commands to the user. Do NOT guess commands — use the ones the project documents.)"

# ----- CI workflows -----
section "CI workflows"
if [[ -d "${REPO}/.github/workflows" ]]; then
  log "GitHub Actions workflows:"
  ls -1 "${REPO}/.github/workflows" 2>/dev/null | tee -a "${OUT}"
fi
for f in .gitlab-ci.yml .circleci/config.yml azure-pipelines.yml Jenkinsfile bitbucket-pipelines.yml; do
  if [[ -e "${REPO}/${f}" ]]; then
    log "CI config found: ${f}"
  fi
done

# Recent workflow timing via gh CLI (if available + authed)
if command -v gh >/dev/null 2>&1 && [[ -d "${REPO}/.git" ]]; then
  if gh auth status >/dev/null 2>&1; then
    log ""
    log "Recent GitHub Actions runs (last 5, any workflow, main branch):"
    # Route through a temp file so we can inspect gh's exit code — piping to tee
    # would mask gh failure behind tee's success and silently produce an empty
    # result that reads as "no runs" rather than "gh couldn't ask".
    GH_TMP="$(mktemp)"
    if (cd "${REPO}" && gh run list --branch main --limit 5 --json workflowName,status,conclusion,createdAt,updatedAt >"${GH_TMP}" 2>/dev/null); then
      if [[ -s "${GH_TMP}" ]]; then
        tee -a "${OUT}" < "${GH_TMP}"
      else
        log "  (gh returned no runs for main — repo may have no CI history on this branch)"
      fi
    else
      log "  (gh run list failed — not a GitHub repo, no auth, or network down)"
    fi
    rm -f "${GH_TMP}"
  else
    log "gh CLI present but not authenticated — skipping run-timing probe"
  fi
fi

# ----- Deploy / backup evidence -----
section "Deploy & backup evidence"
if [[ -d "${REPO}/deploy" ]]; then
  log "deploy/ directory present:"
  ls -1 "${REPO}/deploy" 2>/dev/null | tee -a "${OUT}"
fi
if [[ -d "${REPO}/bin" ]]; then
  log "bin/ scripts (first 20):"
  ls -1 "${REPO}/bin" 2>/dev/null | head -20 | tee -a "${OUT}"
fi
if [[ -d "${REPO}/infra" ]] || [[ -d "${REPO}/terraform" ]] || [[ -d "${REPO}/k8s" ]] || [[ -d "${REPO}/kubernetes" ]] || [[ -d "${REPO}/helm" ]]; then
  log "IaC / deployment directories detected: $(ls -d "${REPO}"/infra "${REPO}"/terraform "${REPO}"/k8s "${REPO}"/kubernetes "${REPO}"/helm 2>/dev/null | tr '\n' ' ')"
fi

log ""
log "Grep for backup/restore/dump evidence (excluding vendor/IDE/skill dirs):"
# `find ... -prune` + `xargs grep` instead of `grep -rlI --exclude-dir=...`
# because the `-r` recursive mode and `--exclude-dir` flag aren't portable
# across GNU grep, BSD grep (macOS), and busybox grep. The find+xargs form
# works everywhere POSIX-ish.
BACKUP_HITS=$(find "${REPO}" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/.venv' \
       -o -path '*/dist' -o -path '*/build' -o -path '*/htmlcov' \
       -o -path '*/.claude' -o -path '*/.idea' -o -path '*/.vscode' \
       -o -path '*/.planning' -o -path '*/reports' \) -prune \
    -o -type f -print0 2>/dev/null \
  | xargs -0 grep -lEi 'pg_dump|mysqldump|mongodump|wal_?archive|restic|borg|rclone|s3 sync|storage[-_ ]box' 2>/dev/null \
  | head -20)
if [[ -n "${BACKUP_HITS}" ]]; then
  echo "${BACKUP_HITS}" | tee -a "${OUT}"
else
  log "  (no hits — absence is evidence; flag disaster-recovery gap in report)"
fi

log ""
log "Dependabot / Renovate configuration:"
for f in .github/dependabot.yml .github/dependabot.yaml renovate.json .renovaterc .renovaterc.json; do
  if [[ -e "${REPO}/${f}" ]]; then
    log "  found: ${f}"
  fi
done

log ""
log "IDE-committed static analysis / editor config (read these for dimension 6):"
IDE_HIT=0
shopt -s nullglob
for match in "${REPO}"/.idea/inspectionProfiles/*.xml \
             "${REPO}"/.vscode/settings.json \
             "${REPO}"/.vscode/extensions.json \
             "${REPO}"/.editorconfig; do
  if [[ -e "${match}" ]]; then
    rel="${match#${REPO}/}"
    lines=$(wc -l < "${match}" 2>/dev/null || echo "?")
    log "  found: ${rel} (${lines} lines)"
    IDE_HIT=1
  fi
done
shopt -u nullglob
if [[ "${IDE_HIT}" = "0" ]]; then
  log "  (no IDE-committed inspection profile / editor config found — team relies on per-contributor editor defaults)"
fi

# ----- Environment tier -----
# Classify what this environment can actually measure, so the skill can pick
# the right Step 2b branch: warm (run tests straight away), partial (ask once
# whether to install missing deps), or cold (skip dynamic validation, report
# dynamic rows as "Not assessable without setup").
section "Environment tier"

if [[ "${TEST_RUNNER_FOUND}" = "1" ]] || [[ "${MONO_HITS}" -gt 0 ]]; then
  TEST_RUNNER_DETECTED=1
fi

if [[ "${HAS_LOC_TOOL}" = "1" ]] && [[ "${TEST_DEPS_INSTALLED}" = "1" ]]; then
  TIER="warm"
  TIER_REASON="LOC tool on PATH and at least one test runner has its deps installed."
elif [[ "${HAS_LOC_TOOL}" = "1" ]] || [[ "${TEST_RUNNER_DETECTED}" = "1" ]]; then
  TIER="partial"
  MISSING=()
  [[ "${HAS_LOC_TOOL}" = "0" ]] && MISSING+=("no LOC tool (tokei/scc/cloc)")
  [[ "${TEST_RUNNER_DETECTED}" = "1" ]] && [[ "${TEST_DEPS_INSTALLED}" = "0" ]] \
    && MISSING+=("test runners detected but deps not installed")
  [[ "${TEST_RUNNER_DETECTED}" = "0" ]] && MISSING+=("no test runner configs detected")
  TIER_REASON="partial — $(IFS='; '; printf '%s' "${MISSING[*]}")."
else
  TIER="cold"
  TIER_REASON="no LOC tool on PATH and no test runner with installed deps."
fi

# Grep-able one-liner per signal. SKILL.md reads these to pick the Step 2b branch.
log "ENVIRONMENT_TIER: ${TIER}"
log "TIER_REASON: ${TIER_REASON}"
log "SIGNAL_LOC_TOOL: $([[ "${HAS_LOC_TOOL}" = "1" ]] && echo yes || echo no)"
log "SIGNAL_TEST_RUNNER_DETECTED: $([[ "${TEST_RUNNER_DETECTED}" = "1" ]] && echo yes || echo no)"
log "SIGNAL_TEST_DEPS_INSTALLED: $([[ "${TEST_DEPS_INSTALLED}" = "1" ]] && echo yes || echo no)"
log ""
log "Tier meaning for the report skill:"
log "  warm    — test execution is viable; offer it per-suite."
log "  partial — one consolidated install-or-skip question before per-suite offers."
log "  cold    — skip dynamic validation; mark Step-2b rows 'Not assessable without setup'."

# ----- Done -----
section "Done"
log "Full output written to: ${OUT}"
