# TkTurners Knowledge Vault

- Shared memory: `TKTURNERS_SHARED_MEMORY.md`
- Private annex: `TKTURNERS_PRIVATE_ANNEX.md`
- Normalized source copies: `source/`
- Audit log: `changelog.jsonl`
- Memory CLI: `/Users/bilal/.openclaw/scripts/knowledge/memoryctl.sh`
- Weekly maintenance helper: `/Users/bilal/.openclaw/scripts/knowledge/weekly_compact.sh`

Rules:
- All agents may read shared memory.
- Sensitive identifiers must stay in private annex.
- Use `memoryctl.sh` for writes.
- Run compact weekly: `/Users/bilal/.openclaw/scripts/knowledge/weekly_compact.sh`
