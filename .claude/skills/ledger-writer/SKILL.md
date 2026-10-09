---
name: ledger-writer
description: How this repo writes to Claude.Agent.Ledger — the writer side only (Add-LedgerEntry -Spool), the entry shape the keeper accepts, and what the hooks must never do. Copied from Claude.Agent.Ledger's README; read-only here. Use whenever a hook or a test writes or reads a policy.* entry, or the ledger fields {phase, tool, kindAction, path, rule, reason, command} change.
version: 0.2.1
---

# Writing to Claude.Agent.Ledger from the policy hooks

Copied from Claude.Agent.Ledger 0.2.1 (`README.md`, Two roles and Chain format). Pester checks that `version`
above equals Claude.Agent.Ledger's `ModuleVersion`; when it does not, recopy from that README, do not edit here.

## The writer side is all the hooks get

- **Writer** (in the agent): `Add-LedgerEntry -Spool <dir> -Kind <string> -Body <hashtable>` appends an
  unsigned `{stamp, kind, body, seq}` line to `<dir>/pending.jsonl` under an exclusive lock. It never reads
  `key.bin` and never touches `ledger.jsonl`. `seq` (in `<dir>/seq`) only grows.
- **Keeper** (in the `ledger` sidecar the agent cannot reach): `Start-LedgerKeeper -Spool -Ledger` owns
  `key.bin`, chains pending lines into `ledger.jsonl` with `prev` and `mac`, and truncates what it consumed.

Add-LedgerEntry throws if given `-Ledger`, or if the `-Spool` directory holds `key.bin` or `ledger.jsonl`.
The hooks spool to `$env:CLAUDE_AGENT_SPOOL`, else `/spool`; never point them at a ledger directory.

## Entry shape

```json
{"stamp":"2026-10-08T12:00:00.0000000Z","kind":"policy.deny","body":{"phase":"pre","tool":"Bash","kindAction":"File.delete","path":"/work/x","rule":"rules[2]","reason":"...","command":"rm /work/x"},"seq":7}
```

- `kind`: free-form dotted name. This repo writes only `policy.allow`, `policy.deny`, `policy.witness`.
- `body`: the hashtable passed to `Add-LedgerEntry`, as JSON. Keep it a flat hashtable of strings and nulls.
- The keeper chains the writer's exact bytes; a line that is not exactly `{stamp, kind, body, seq}` becomes a
  `ledger.rejected` entry carrying the raw text. Never write the spool by hand.

## Rules

- The agent can lie in, omit, or edit spooled lines before the keeper takes them (Claude.Agent.Ledger design 3).
  A policy entry is evidence of what the hook decided, not proof the hook ran for every call.
- The pre hook writes its entry before it answers, and fails closed (exit 2) if the write throws.
- `seq` is the writer's and must run 1, 2, 3, ... in the ledger; `Test-Ledger` reports anything else as
  `seq-gap`. Never write or edit `<Spool>/seq` or `pending.jsonl` from a hook.
- Reading or verifying the ledger (`Get-Ledger`, `Test-Ledger`) happens on the host, never in a hook.
