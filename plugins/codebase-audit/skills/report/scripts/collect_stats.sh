#!/usr/bin/env bash
# Collect summary stats for a git repo quality assessment.
#
# Usage:
#   collect_stats.sh <repo-path>
#
# Produces human-readable output to stdout and writes the same to
# /tmp/quality-assessment-stats.txt for the caller to reference.
#
# Sections:
#   - Repo identity (name, branch, commit, remote)
#   - LOC breakdown (tokei -> scc -> cloc -> git+wc fallback)
#   - Test directory LOC (heuristic)
#   - Git activity (commits, contributors) for last 90 days
#   - Dependency manifests + lockfile presence
#   - Coverage artifact search
#   - CI workflow discovery + recent run timing (if gh is available)
#   - Docker / deploy artifacts
#   - Backup / restore evidence (grep only — does not assume tools)
#
# The script is read-only on the target repo. It does not run tests
# or install anything without asking.

set -uo pipefail

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

OUT=/tmp/quality-assessment-stats.txt
: > "${OUT}"

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
  for d in $(printf '%s\n' "${TEST_DIRS[@]}" | sort -u); do
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
  done
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
    (cd "${REPO}" && gh run list --branch main --limit 5 --json workflowName,status,conclusion,createdAt,updatedAt 2>/dev/null) | tee -a "${OUT}" || log "  (gh run list failed — not a GitHub repo or no auth)"
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
BACKUP_HITS=$(grep -rlIiE 'pg_dump|mysqldump|mongodump|wal_?archive|restic|borg|rclone|s3 sync|storage[-_ ]box' \
  --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv \
  --exclude-dir=dist --exclude-dir=build --exclude-dir=htmlcov \
  --exclude-dir=.claude --exclude-dir=.idea --exclude-dir=.vscode \
  --exclude-dir=.planning --exclude-dir=reports \
  "${REPO}" 2>/dev/null | head -20)
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

# ----- Done -----
section "Done"
log "Full output written to: ${OUT}"
