#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-$HOME/.openclaw}"
NODE22="${OPENCLAW_NODE22:-$HOME/.nvm/versions/node/v22.22.0/bin/node}"
OPENCLAW_JS="${OPENCLAW_JS:-$HOME/.nvm/versions/node/v22.22.0/lib/node_modules/openclaw/dist/index.js}"
BRANCH="${OPENCLAW_GITHUB_BRANCH:-main}"
LOG_DIR="$ROOT/logs"
STATE_DIR="$ROOT/.state"
mkdir -p "$LOG_DIR" "$STATE_DIR" "$ROOT/backups"
LOG_FILE="$LOG_DIR/self-heal.log"

log() {
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" | tee -a "$LOG_FILE"
}

health_ok() {
  "$NODE22" "$OPENCLAW_JS" health --json 2>/dev/null | jq -e '.ok == true' >/dev/null 2>&1
}

cd "$ROOT"

if health_ok; then
  git rev-parse HEAD > "$STATE_DIR/last_healthy_commit" 2>/dev/null || true
  log "Health OK"
  "$ROOT/scripts/github_sync.sh" || true
  exit 0
fi

log "Health check failed. Starting repair workflow."

# Snapshot current state before repair attempt
backup_file="$ROOT/backups/openclaw-backup-$(date -u +"%Y%m%dT%H%M%SZ").tar.gz"
tar -czf "$backup_file" openclaw.json agents 2>/dev/null || true
log "Backup created: $backup_file"

# Try restoring from last healthy commit first, then origin/main
restore_ref=""
if [[ -f "$STATE_DIR/last_healthy_commit" ]]; then
  restore_ref="$(cat "$STATE_DIR/last_healthy_commit" 2>/dev/null || true)"
fi

if [[ -n "$restore_ref" ]] && git cat-file -e "$restore_ref^{commit}" 2>/dev/null; then
  git checkout "$restore_ref" -- openclaw.json agents || true
  log "Restored from last healthy commit: $restore_ref"
else
  git fetch origin "$BRANCH" || true
  if git show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    git checkout "origin/$BRANCH" -- openclaw.json agents || true
    log "Restored from origin/$BRANCH"
  else
    log "ERROR: no recoverable git reference found"
  fi
fi

# Restart gateway (launchd)
launchctl kickstart -k "gui/$(id -u)/ai.openclaw.gateway" || true
sleep 2

if health_ok; then
  log "Repair successful; syncing safe tracked files"
  "$ROOT/scripts/github_sync.sh" || true
  exit 0
fi

log "ERROR: repair attempt did not recover gateway health"
exit 1
