# Workflow Engine (Autonomous E2E)

This adds a staged workflow runtime with persisted state and idempotent re-runs.

## Stage model
`intake -> classify -> plan -> configure_tools -> execute -> verify -> deliver -> log`

## What is persisted
- Run records: `/Users/bilal/.openclaw/workflows/state/runs/<runId>.json`
- Idempotency map: `/Users/bilal/.openclaw/workflows/state/index.json`
- Tool bootstrap markers: `/Users/bilal/.openclaw/workflows/state/tools/*.ok`
- Delivery summaries: `/Users/bilal/.openclaw/workflows/outbox/<runId>.md`
- Event log: `/Users/bilal/.openclaw/workflows/logs/events.jsonl`

## Commands
Run a workflow:
```bash
node /Users/bilal/.openclaw/scripts/workflow_engine.mjs run autonomous-e2e --input "write a blog on BIM Automation in Autodesk"
```

Resume an existing failed run:
```bash
node /Users/bilal/.openclaw/scripts/workflow_engine.mjs run autonomous-e2e --resume <runId> --input "same input"
```

Force execution even if idempotency key already completed:
```bash
node /Users/bilal/.openclaw/scripts/workflow_engine.mjs run autonomous-e2e --input "..." --force
```

## Safe auto-configuration
Tool auto-configuration is allowlist-only and definition-driven:
- No arbitrary user-provided shell execution.
- Commands are fixed in workflow definition JSON.

Definition file:
`/Users/bilal/.openclaw/workflows/definitions/autonomous-e2e.json`

## Autonomous operations
The `execute` stage dispatches a one-shot cron task to `personal-assistant` using:
`/Users/bilal/.openclaw/scripts/workflow_ops/dispatch_task.sh`

That keeps orchestration centralized while still enabling autonomous execution.

## Feedback-driven self-improvement
Submit feedback:
```bash
node /Users/bilal/.openclaw/scripts/workflow_feedback_loop.mjs submit \
  --workflow-id autonomous-e2e \
  --run-id <runId> \
  --score 4 \
  --feedback "Needs more source links and tighter summaries"
```

Run improvement analysis manually:
```bash
node /Users/bilal/.openclaw/scripts/workflow_feedback_loop.mjs improve --workflow-id autonomous-e2e
```

Auto-apply low-risk improvements:
```bash
node /Users/bilal/.openclaw/scripts/workflow_feedback_loop.mjs improve --workflow-id autonomous-e2e --auto-apply --max-changes 2
```

When `selfImprove.enabled=true` in workflow definition, each workflow run triggers this analysis automatically at the `log` stage.

## Important constraints
- This engine is robust but intentionally guarded.
- High-risk operations should still require explicit user confirmation (`OPS:` gate on WhatsApp).
