# TkTurners Skills Rollout

Date: 2026-02-20
Scope: business operations, content, brand, and engineering enablement skills.

## Rollout Bundle

| Skill | TkTurners Use Case | Requirements | Config Work | Validation |
|---|---|---|---|---|
| `1password` | Centralized secret retrieval for agents/scripts | `op` binary | Enable skill entry | `openclaw skills info 1password` shows Ready |
| `github` | Repo issues/PR/CI operations | `gh` binary + `gh auth login` | Enable skill entry | `openclaw skills info github` shows Ready |
| `gh-issues` | Automated issue triage/fix/PR pipeline | `gh`, `git`, `curl`, `GH_TOKEN` | Enable skill entry; optionally set `skills.entries.gh-issues.apiKey` | `openclaw skills info gh-issues` shows Ready |
| `blogwatcher` | Competitor/blog monitoring | `go` + `blogwatcher` binary | Enable skill entry | `openclaw skills info blogwatcher` shows Ready |
| `summarize` | URL/video/article summarization + transcript fallback | `summarize` binary | Enable skill entry | `openclaw skills info summarize` shows Ready |
| `openai-image-gen` | Brand visuals and campaign asset batches | `python3`, `OPENAI_API_KEY` | Enable skill entry | `openclaw skills info openai-image-gen` shows Ready |
| `openai-whisper-api` | Audio transcription for meetings/content | `curl`, `OPENAI_API_KEY` | Enable skill entry | `openclaw skills info openai-whisper-api` shows Ready |
| `notion` | Knowledge base/pages/data source automations | `NOTION_API_KEY` | Enable skill entry | `openclaw skills info notion` shows Ready |
| `mcporter` | MCP server operations and codegen | `mcporter` binary | Enable skill entry | `openclaw skills info mcporter` shows Ready |
| `model-usage` | Per-model spend visibility via CodexBar | `codexbar` binary | Enable skill entry | `openclaw skills info model-usage` shows Ready |

## Execution Notes

- Configure in both:
  - `/Users/bilal/.openclaw/openclaw.json`
  - `/Users/bilal/.openclaw/openclaw.template.json`
- Keep rollout safe: install binaries where possible, but do not inject fake API keys.
- After binary installs and config patches, run:
  - `openclaw skills check --json`
  - targeted `openclaw skills info <name>` checks.

## Execution Status (2026-02-20)

- Skills check summary: `total=52`, `eligible=16`, `missingRequirements=36`.
- Rollout bundle status:
  - Ready now: `1password`, `github`, `gh-issues`, `blogwatcher`, `summarize`, `mcporter`, `model-usage`.
  - Blocked by credentials only: `openai-image-gen` (`OPENAI_API_KEY`), `openai-whisper-api` (`OPENAI_API_KEY`), `notion` (`NOTION_API_KEY`).
- Installed during rollout:
  - `brew install gh go`
  - `brew install --cask 1password-cli codexbar`
  - `go install github.com/Hyaxia/blogwatcher/cmd/blogwatcher@latest`
  - `brew tap steipete/tap && brew install steipete/tap/summarize`
  - `npm install -g mcporter` (linked to `/opt/homebrew/bin/mcporter`)
- Slack skipped per owner request.

## Credential/Channel Blockers To Be Provided By Owner

- `OPENAI_API_KEY` for `openai-image-gen`, `openai-whisper-api`
- `NOTION_API_KEY` for `notion`
- `GH_TOKEN` (if not using `gh auth`) for `gh-issues` and `github`
