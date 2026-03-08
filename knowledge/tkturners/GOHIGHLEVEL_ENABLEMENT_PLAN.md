# GoHighLevel Enablement Plan

Date: 2026-02-20
Status: Implemented (updated 2026-02-21)

## Decision
- Implement both:
  - a reusable `gohighlevel` skill
  - a dedicated `role-gohighlevel-operator` agent

This supports direct skill use and role-based delegation from orchestration agents.

## Public Interfaces

1. Skill: `/Users/bilal/.agents/skills/gohighlevel/SKILL.md`
2. API control script: `/Users/bilal/.openclaw/scripts/integrations/ghlctl.sh`
3. Agent prompt contract: `/Users/bilal/.openclaw/agents/role-gohighlevel-operator/workspace/AGENTS.md`
4. Config registration:
   - `/Users/bilal/.openclaw/openclaw.json`
   - `/Users/bilal/.openclaw/openclaw.template.json`

## Command Contract (`ghlctl.sh`)

- `auth-check [--location <id>] [--live] [--dry-run]`
- `oauth-authorize-url --client-id <id> --redirect-uri <uri> [--user-type Company|Location] [--scope "<space separated scopes>"] [--state <text>] [--auth-url <url>]`
- `oauth-exchange --client-id <id> --client-secret <secret> --code <auth_code> --redirect-uri <uri> [--user-type Company|Location] [--env-file <abs_path>] [--show-tokens] [--dry-run]`
- `oauth-refresh --client-id <id> --client-secret <secret> [--refresh-token <token>] [--user-type Company|Location] [--env-file <abs_path>] [--show-tokens] [--dry-run]`
- `request --method <METHOD> --path </path> [--query "k=v&..."] [--data '<json>'] [--dry-run]`
- `get-location --location <id> [--dry-run]`
- `create-contact --location <id> [--first-name <v>] [--last-name <v>] [--email <v>] [--phone <v>] [--tags a,b] [--dry-run]`
- `list-opportunities [--location <id>] [--limit <n>] [--pipeline-id <id>] [--status open|won|lost|abandoned|all] [--dry-run]`
- `get-opportunity --id <id> [--dry-run]`

## Security and Operations Defaults

- Secrets are stored in local private env file only (`/Users/bilal/.openclaw/.env`) and runtime process env.
- Runtime env-based credentials:
  - direct token mode: `GHL_API_TOKEN`
  - OAuth mode: `GHL_CLIENT_ID`, `GHL_CLIENT_SECRET`, `GHL_REFRESH_TOKEN` (+ exchanged access token)
  - optional: `GHL_LOCATION_ID`, `GHL_API_BASE`, `GHL_API_VERSION`
- Write-safe behavior by process:
  - run dry-run first for writes
  - then execute live call only when confirmed

## Validation Targets

1. Script executable and syntactically valid.
2. Config JSON remains valid.
3. Skill discoverable in OpenClaw.
4. Agent is listed in OpenClaw config.
5. Regression smoke suite still passes.
