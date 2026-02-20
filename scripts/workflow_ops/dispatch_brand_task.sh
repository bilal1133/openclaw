#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-/Users/bilal/.openclaw}"
NODE22="${OPENCLAW_NODE22:-/Users/bilal/.nvm/versions/node/v22.22.0/bin/node}"
OPENCLAW_JS="${OPENCLAW_JS:-/Users/bilal/.nvm/versions/node/v22.22.0/lib/node_modules/openclaw/dist/index.js}"

CADENCE="${1:-daily}"
BRAND_ID="${2:-}"
TASK="${3:-}"
RUN_DATE="${4:-$(date +%F)}"
TRIGGER_SOURCE="${5:-manual}"
RUN_ID="${WF_RUN_ID:-manual-$(date +%s)}"

if [[ "$CADENCE" != "approval-reminder" && -z "$BRAND_ID" ]]; then
  echo '{"ok":false,"error":"missing brand_id"}'
  exit 1
fi

BRAND_ROOT="$ROOT/brands/$BRAND_ID"
PROFILE_DIR="$BRAND_ROOT/profile"
KPI_INBOX_DIR="$BRAND_ROOT/kpi/inbox"
RUNS_DIR="$BRAND_ROOT/runs"
ARTIFACT_ROOT="$BRAND_ROOT/artifacts/$RUN_DATE/$RUN_ID"
RUN_STATE_DIR="$RUNS_DIR/$RUN_ID"

mkdir -p \
  "$ROOT/brands/_shared" \
  "$ROOT/workflows/approvals/pending" \
  "$ROOT/workflows/approvals/approved" \
  "$ROOT/workflows/approvals/rejected" \
  "$ROOT/workflows/approvals/held"

if [[ -n "$BRAND_ID" ]]; then
  mkdir -p "$PROFILE_DIR" "$KPI_INBOX_DIR" "$RUNS_DIR" "$ARTIFACT_ROOT" "$RUN_STATE_DIR"
fi

if [[ "$CADENCE" == "onboard" && -n "$BRAND_ID" ]]; then
  DOSSIER="$PROFILE_DIR/brand-dossier.md"
  PRINCIPLE="$PROFILE_DIR/key-principle.md"
  if [[ ! -f "$DOSSIER" ]]; then
    cat > "$DOSSIER" <<DOSSIER
---
brand_id: $BRAND_ID
brand_name: ${BRAND_ID//-/ }
timezone: Asia/Karachi
owner_name: Brand Owner
owner_whatsapp: "+10000000000"
approval_sla_hours: 24
channels:
  - blog
  - linkedin
  - email
social_channels:
  - x
  - instagram
  - youtube_shorts
compliance_level: strict
sharing_policy: patterns_only
---

## Key Principle
One clear value promise that all outputs must reinforce.

## Voice and Tone
Professional, practical, direct.

## ICP
Define ideal customer profile and purchase triggers.

## Offers
List core offers and package boundaries.

## Messaging Do/Don't
- Do: use evidence-backed claims.
- Don't: promise guaranteed outcomes.

## Content Pillars
- Pain points
- How-to frameworks
- Case evidence

## Proof Sources
List approved proof sources and references.

## Approval Rules
Final approval by brand owner within 24 hours.

## KPI Definitions
Define KPI formulas and data source mapping.
DOSSIER
  fi

  if [[ ! -f "$PRINCIPLE" ]]; then
    cat > "$PRINCIPLE" <<'PRINCIPLE'
# Brand Key Principle

State the non-negotiable principle that guides messaging, design, and client success decisions.
PRINCIPLE
  fi
fi

if [[ -n "$BRAND_ID" ]]; then
  printf 'section,claim,source,url,date\n' > "$ARTIFACT_ROOT/sources.csv"

  cat > "$ARTIFACT_ROOT/technical-writer.md" <<'FILE'
# Technical Writer Artifact

Status: queued for role agent execution.
FILE

  cat > "$ARTIFACT_ROOT/marketing-pack.md" <<'FILE'
# Marketing Pack

Status: queued for role agent execution.
FILE

  cat > "$ARTIFACT_ROOT/brand-design-pack.md" <<'FILE'
# Brand Design Pack

Status: queued for role agent execution.
FILE

  if [[ "$CADENCE" == "weekly" || "$CADENCE" == "monthly" ]]; then
    cat > "$ARTIFACT_ROOT/client-success-report.md" <<'FILE'
# Client Success Report

Status: queued for role agent execution.
FILE
  fi

  cat > "$ARTIFACT_ROOT/publish-bundle.md" <<'FILE'
# Publish Bundle

Status: blocked until approval.
FILE

  cat > "$ARTIFACT_ROOT/approval-summary.md" <<'FILE'
# Approval Summary

Status: pending assembly.
FILE

  "$NODE22" - <<'NODE' "$ARTIFACT_ROOT/run-manifest.json" "$RUN_ID" "$BRAND_ID" "$CADENCE" "$RUN_DATE"
const fs = require('node:fs');
const outPath = process.argv[2];
const runId = process.argv[3];
const brandId = process.argv[4];
const cadence = process.argv[5];
const runDate = process.argv[6];
const now = new Date().toISOString();
const roles = cadence === 'weekly' || cadence === 'monthly'
  ? ['technical-writer', 'marketing-manager', 'brand-designer', 'client-success-manager']
  : ['technical-writer', 'marketing-manager', 'brand-designer'];
const manifest = {
  run_id: runId,
  brand_id: brandId,
  cadence,
  run_date: runDate,
  roles_executed: roles,
  artifacts: {
    technical_writer: 'technical-writer.md',
    marketing_pack: 'marketing-pack.md',
    brand_design_pack: 'brand-design-pack.md',
    client_success_report: cadence === 'weekly' || cadence === 'monthly' ? 'client-success-report.md' : null,
    publish_bundle: 'publish-bundle.md',
    sources: 'sources.csv',
    approval_summary: 'approval-summary.md'
  },
  guardrail_results: {
    ok: false,
    reason: 'queued',
    checks: []
  },
  approval_id: null,
  status: 'queued',
  started_at: now,
  finished_at: null
};
fs.writeFileSync(outPath, JSON.stringify(manifest, null, 2));
NODE

  "$NODE22" - <<'NODE' "$BRAND_ROOT/runs/latest-status.json" "$RUN_ID" "$BRAND_ID" "$CADENCE" "$RUN_DATE"
const fs = require('node:fs');
const outPath = process.argv[2];
const runId = process.argv[3];
const brandId = process.argv[4];
const cadence = process.argv[5];
const runDate = process.argv[6];
const now = new Date().toISOString();
fs.writeFileSync(outPath, JSON.stringify({
  brand_id: brandId,
  run_id: runId,
  cadence,
  run_date: runDate,
  status: 'queued',
  updated_at: now
}, null, 2));
NODE
fi

PAYLOAD="$($NODE22 - <<'NODE' "$CADENCE" "$BRAND_ID" "$RUN_DATE" "$TRIGGER_SOURCE" "$TASK" "$RUN_ID"
const cadence = process.argv[2] || 'daily';
const brandId = process.argv[3] || '';
const runDate = process.argv[4] || new Date().toISOString().slice(0, 10);
const triggerSource = process.argv[5] || 'manual';
const task = process.argv[6] || '';
const runId = process.argv[7] || '';
const payload = {
  kind: 'brand_workflow',
  cadence,
  brand_id: brandId,
  run_date: runDate,
  trigger_source: triggerSource,
  task,
  run_id: runId
};
process.stdout.write(JSON.stringify(payload));
NODE
)"

MESSAGE="RUN_BRAND_WORKFLOW $PAYLOAD"

RES="$($NODE22 "$OPENCLAW_JS" cron add \
  --name "brand-${BRAND_ID:-global}-${CADENCE}-${RUN_ID:0:8}" \
  --description "one-shot brand workflow dispatch" \
  --delete-after-run \
  --agent brand-orchestrator \
  --session isolated \
  --wake now \
  --at 30s \
  --message "$MESSAGE" \
  --no-deliver 2>/dev/null)"

JOB_ID="$(printf '%s' "$RES" | jq -r '.id // empty')"
if [[ -z "$JOB_ID" ]]; then
  echo '{"ok":false,"error":"failed to create brand workflow dispatch job"}'
  exit 1
fi

echo "{\"ok\":true,\"jobId\":\"$JOB_ID\",\"brandId\":\"$BRAND_ID\",\"cadence\":\"$CADENCE\",\"runId\":\"$RUN_ID\",\"artifactDir\":\"$ARTIFACT_ROOT\"}"
