#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-$HOME/.openclaw}"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/github-sync.log"

log() {
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" | tee -a "$LOG_FILE"
}

cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "ERROR: not a git repository: $ROOT"
  exit 1
fi

REMOTE_URL="${OPENCLAW_GITHUB_REMOTE:-}"
BRANCH="${OPENCLAW_GITHUB_BRANCH:-main}"
SAFE_PATHS=(
  ".gitignore"
  "README.md"
  "GITHUB_SYNC_SETUP.md"
  "WORKFLOW_ENGINE.md"
  "openclaw.template.json"
  "agents"
  "scripts"
  "cron/jobs.json"
  "workflows/definitions"
)

if ! git remote get-url origin >/dev/null 2>&1; then
  if [[ -z "$REMOTE_URL" ]]; then
    log "WARN: no origin remote configured; set OPENCLAW_GITHUB_REMOTE to bootstrap"
    exit 0
  fi
  git remote add origin "$REMOTE_URL"
  log "Configured origin remote"
fi

# Keep branch consistent
current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "$BRANCH")"
if [[ "$current_branch" != "$BRANCH" ]]; then
  git checkout -B "$BRANCH"
fi

# Ensure pull strategy is stable for automation
git config pull.rebase true
git config rebase.autoStash true
git config fetch.prune true

# Stage and commit local changes from safe paths only
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A -- "${SAFE_PATHS[@]}" 2>/dev/null || true
  if [[ -n "$(git diff --cached --name-only)" ]]; then
    if git diff --cached | rg -i '(sk-or-v1-|api[_-]?key|authorization:|bearer\s+[a-z0-9._-]+)' >/dev/null 2>&1; then
      log "ERROR: potential secret detected in staged diff; aborting sync commit"
      git reset >/dev/null 2>&1 || true
      exit 1
    fi
    git commit -m "chore(sync): automated snapshot $(date -u +"%Y-%m-%dT%H:%M:%SZ")" || true
    log "Committed safe local changes"
  else
    log "No safe tracked changes to commit"
  fi
fi

# Sync with remote safely
if git ls-remote --exit-code origin >/dev/null 2>&1; then
  git fetch origin "$BRANCH" || true
  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git pull --rebase --autostash origin "$BRANCH" || {
      log "WARN: pull --rebase failed; keeping local state"
    }
  fi

  git push -u origin "$BRANCH" || {
    log "WARN: push failed (auth/permission/network)."
    exit 1
  }
  log "Sync complete: pushed to origin/$BRANCH"
else
  log "WARN: cannot reach origin (network/auth)."
  exit 1
fi
