# TkTurners Knowledge Vault

- Shared memory: `TKTURNERS_SHARED_MEMORY.md`
- Private annex: `TKTURNERS_PRIVATE_ANNEX.md`
- Normalized source copies: `source/`
- Audit log: `changelog.jsonl`

Rules:
- All agents may read shared memory.
- Sensitive identifiers must stay in private annex.
- Use `memoryctl.sh` for writes.
