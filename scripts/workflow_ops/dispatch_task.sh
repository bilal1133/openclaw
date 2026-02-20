#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-/Users/bilal/.openclaw}"
NODE22="${OPENCLAW_NODE22:-/Users/bilal/.nvm/versions/node/v22.22.0/bin/node}"
OPENCLAW_JS="${OPENCLAW_JS:-/Users/bilal/.nvm/versions/node/v22.22.0/lib/node_modules/openclaw/dist/index.js}"

ROUTE="${1:-general}"
TASK="${2:-}"
RUN_ID="${WF_RUN_ID:-manual}"

if [[ -z "$TASK" ]]; then
  echo '{"ok":false,"error":"missing task"}'
  exit 1
fi

TARGET_MESSAGE="$TASK"
if [[ "$ROUTE" == "ops" && "$TASK" != OPS:* ]]; then
  TARGET_MESSAGE="OPS: $TASK"
fi

# One-shot job at +30s so it is queued and executed by gateway scheduler.
RES="$($NODE22 "$OPENCLAW_JS" cron add \
  --name "wf-${RUN_ID:0:8}-${ROUTE}" \
  --description "one-shot workflow dispatch" \
  --delete-after-run \
  --agent personal-assistant \
  --session isolated \
  --wake now \
  --at 30s \
  --message "$TARGET_MESSAGE" \
  --announce \
  --channel whatsapp \
  --to "+923248473417" \
  --best-effort-deliver 2>/dev/null)"

JOB_ID="$(printf '%s' "$RES" | jq -r '.id // empty')"
if [[ -z "$JOB_ID" ]]; then
  echo '{"ok":false,"error":"failed to create cron dispatch job"}'
  exit 1
fi

echo "{\"ok\":true,\"jobId\":\"$JOB_ID\",\"route\":\"$ROUTE\",\"runId\":\"$RUN_ID\"}"
