#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-$HOME/.openclaw}"
PLIST_PATH="$HOME/Library/LaunchAgents/ai.openclaw.github-autosync.plist"

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>ai.openclaw.github-autosync</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$ROOT/scripts/self_heal.sh</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>OPENCLAW_ROOT</key>
    <string>$ROOT</string>
  </dict>

  <key>StartInterval</key>
  <integer>300</integer>

  <key>RunAtLoad</key>
  <true/>

  <key>StandardOutPath</key>
  <string>$ROOT/logs/github-autosync.out.log</string>

  <key>StandardErrorPath</key>
  <string>$ROOT/logs/github-autosync.err.log</string>
</dict>
</plist>
PLIST

launchctl unload "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl load "$PLIST_PATH"
launchctl start ai.openclaw.github-autosync || true

echo "Installed and started: ai.openclaw.github-autosync"
echo "Edit remote/branch via env vars before relying on full sync:"
echo "  OPENCLAW_GITHUB_REMOTE=https://github.com/<owner>/<repo>.git"
echo "  OPENCLAW_GITHUB_BRANCH=main"
