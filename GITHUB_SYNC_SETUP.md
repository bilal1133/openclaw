# GitHub Auto-Sync + Self-Heal Setup (OpenClaw)

## What this does
- Periodically (every 5 minutes) runs a health + sync loop.
- If OpenClaw health is OK:
  - commits local changes
  - pulls/rebases from GitHub
  - pushes back to GitHub
- If OpenClaw health fails:
  - creates a local backup tarball
  - restores key config files from last healthy commit (or `origin/main`)
  - restarts gateway
  - re-syncs to GitHub on success

## Files added
- `scripts/github_sync.sh`
- `scripts/self_heal.sh`
- `scripts/install_github_autosync_launchd.sh`
- `.gitignore`

## Why this pattern
- OpenClaw hooks are event-driven, but error hooks are not a stable trigger yet.
- OpenClaw cron is best for agent tasks, while this is system-level git+gateway maintenance.
- Launchd is the most reliable scheduler on macOS for persistent service loops.

## Required one-time setup
1. Configure git remote:
   - `git remote add origin <your-github-repo-url>`
2. Ensure authentication:
   - Preferred: SSH (`git@github.com:owner/repo.git`)
   - Or HTTPS with Git Credential Manager
3. Create first baseline commit:
   - `git add -A && git commit -m "chore: baseline openclaw state"`
   - `git push -u origin main`
4. Install autosync service:
   - `bash scripts/install_github_autosync_launchd.sh`

## Recommended security
- Use a **private repo**.
- Review `.gitignore` and confirm no secrets are tracked.
- Do not rely on `openclaw.json` being safe to sync; it may contain local auth/runtime secrets and is not part of the autosync safe-path allowlist.
- If `openclaw.json` is already tracked, untrack it or move sensitive values out before syncing to a remote.
- Default autosync scope is intentionally narrow (`agents/`, `scripts/`, `cron/jobs.json`, workflow definitions, and selected docs/templates).

## Logs
- `logs/github-sync.log`
- `logs/self-heal.log`
- `logs/github-autosync.out.log`
- `logs/github-autosync.err.log`
