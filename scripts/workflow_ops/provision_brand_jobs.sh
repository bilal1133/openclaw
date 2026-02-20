#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-/Users/bilal/.openclaw}"
NODE22="${OPENCLAW_NODE22:-/Users/bilal/.nvm/versions/node/v22.22.0/bin/node}"
OPENCLAW_JS="${OPENCLAW_JS:-/Users/bilal/.nvm/versions/node/v22.22.0/lib/node_modules/openclaw/dist/index.js}"

BRAND_ID="${1:-}"
TZ_NAME="${2:-Asia/Karachi}"
OWNER_WHATSAPP="${3:-}"

if [[ -z "$BRAND_ID" ]]; then
  echo "Usage: provision_brand_jobs.sh <brand_id> [timezone] [owner_whatsapp]"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required"
  exit 1
fi

brand_message() {
  local cadence="$1"
  local trigger="$2"
  "$NODE22" - <<'NODE' "$BRAND_ID" "$cadence" "$trigger"
const brandId = process.argv[2];
const cadence = process.argv[3];
const trigger = process.argv[4];
const payload = {
  kind: 'brand_workflow',
  brand_id: brandId,
  cadence,
  run_date: new Date().toISOString().slice(0, 10),
  trigger_source: trigger,
  task: cadence === 'approval-reminder' ? 'Check pending approvals and enforce SLA.' : `Run ${cadence} brand workflow package.`
};
process.stdout.write(`RUN_BRAND_WORKFLOW ${JSON.stringify(payload)}`);
NODE
}

find_job_id_by_name() {
  local name="$1"
  "$NODE22" "$OPENCLAW_JS" cron list --all --json 2>/dev/null | jq -r --arg n "$name" '.jobs[]? | select(.name == $n) | .id' | head -n 1
}

ensure_job() {
  local name="$1"
  local desc="$2"
  local expr="$3"
  local message="$4"

  local existing_id
  existing_id="$(find_job_id_by_name "$name")"

  if [[ -n "$existing_id" ]]; then
    "$NODE22" "$OPENCLAW_JS" cron edit "$existing_id" \
      --name "$name" \
      --description "$desc" \
      --enable \
      --agent brand-orchestrator \
      --session isolated \
      --wake now \
      --cron "$expr" \
      --tz "$TZ_NAME" \
      --exact \
      --message "$message" \
      --no-deliver >/dev/null
    echo "$existing_id"
    return
  fi

  local res
  res="$($NODE22 "$OPENCLAW_JS" cron add \
    --name "$name" \
    --description "$desc" \
    --agent brand-orchestrator \
    --session isolated \
    --wake now \
    --cron "$expr" \
    --tz "$TZ_NAME" \
    --exact \
    --message "$message" \
    --no-deliver 2>/dev/null)"

  printf '%s' "$res" | jq -r '.id // empty'
}

mkdir -p "$ROOT/brands/$BRAND_ID/profile" "$ROOT/brands/$BRAND_ID/kpi/inbox" "$ROOT/brands/$BRAND_ID/runs" "$ROOT/brands/$BRAND_ID/artifacts"

DAILY_NAME="brand-${BRAND_ID}-daily-v1"
WEEKLY_NAME="brand-${BRAND_ID}-weekly-cs-v1"
MONTHLY_NAME="brand-${BRAND_ID}-monthly-qbr-v1"
REMINDER_NAME="brand-${BRAND_ID}-approval-reminder-v1"

DAILY_ID="$(ensure_job "$DAILY_NAME" "Daily brand run" "0 8 * * *" "$(brand_message daily cron)")"
WEEKLY_ID="$(ensure_job "$WEEKLY_NAME" "Weekly client success run" "0 10 * * 1" "$(brand_message weekly cron)")"
MONTHLY_ID="$(ensure_job "$MONTHLY_NAME" "Monthly QBR run" "0 10 1 * *" "$(brand_message monthly cron)")"
REMINDER_ID="$(ensure_job "$REMINDER_NAME" "Hourly approval SLA checker" "0 * * * *" "$(brand_message approval-reminder cron)")"

"$NODE22" - <<'NODE' "$BRAND_ID" "$TZ_NAME" "$OWNER_WHATSAPP" "$DAILY_ID" "$WEEKLY_ID" "$MONTHLY_ID" "$REMINDER_ID"
const fs = require('node:fs');
const path = require('node:path');
const root = process.env.OPENCLAW_ROOT || '/Users/bilal/.openclaw';
const brandId = process.argv[2];
const tz = process.argv[3];
const owner = process.argv[4] || '';
const daily = process.argv[5] || '';
const weekly = process.argv[6] || '';
const monthly = process.argv[7] || '';
const reminder = process.argv[8] || '';
const outPath = path.join(root, 'brands', brandId, 'runs', 'scheduler-jobs.json');
const payload = {
  brand_id: brandId,
  timezone: tz,
  owner_whatsapp: owner,
  jobs: {
    daily,
    weekly,
    monthly,
    approval_reminder: reminder
  },
  updated_at: new Date().toISOString()
};
fs.writeFileSync(outPath, JSON.stringify(payload, null, 2));
NODE

echo "{\"ok\":true,\"brand_id\":\"$BRAND_ID\",\"timezone\":\"$TZ_NAME\",\"jobs\":{\"daily\":\"$DAILY_ID\",\"weekly\":\"$WEEKLY_ID\",\"monthly\":\"$MONTHLY_ID\",\"approval_reminder\":\"$REMINDER_ID\"}}"
