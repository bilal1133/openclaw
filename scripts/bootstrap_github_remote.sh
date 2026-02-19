#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-$HOME/.openclaw}"
REMOTE_URL="${1:-${OPENCLAW_GITHUB_REMOTE:-}}"
BRANCH="${2:-${OPENCLAW_GITHUB_BRANCH:-main}}"

if [[ -z "$REMOTE_URL" ]]; then
  echo "Usage: $0 <github-remote-url> [branch]"
  echo "Example: $0 git@github.com:owner/openclaw-config.git main"
  exit 1
fi

cd "$ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git init -b "$BRANCH"
fi

git config pull.rebase true
git config rebase.autoStash true
git config fetch.prune true

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

if ! git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  git checkout -B "$BRANCH"
fi

git add -A
if [[ -n "$(git status --porcelain)" ]]; then
  git commit -m "chore: baseline openclaw sync state"
fi

git push -u origin "$BRANCH"

echo "Remote configured and baseline pushed to origin/$BRANCH"
