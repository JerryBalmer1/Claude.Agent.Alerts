# CLAUDE.md

PowerShell 7.4+ module: reads a Claude.Agent ledger, raises findings from rules, writes them as a GraphNode
layer. One of five sibling repos:

- `Claude.Agent` builds the agent image and runs the end-to-end check; its Alerts task runs this module on the host.
- `Claude.Agent.Ledger` is the ledger this reads (never writes).
- `Claude.Agent.Network` is the mitmproxy capture sidecar.
- `Claude.Agent.Policy` is the tool policy whose `policy.*` entries most rules read.
- `Claude.Agent.Alerts` (this repo).

`Graph.Node` (GraphNode) is a read-only reference: the envelope shape, `schemas/ids.md`, `cmd/graphnode`.
All are expected side by side (e.g. `C:\__Code\`).

## Layout

- `src/Claude.Agent.Alerts/` module. `Public/*.ps1` are exported (list them in the `.psd1` too), `Private/*.ps1`
  are helpers. `rules/default.yaml` and `ontology.yaml` ship inside the module.
- `tests/` Pester 5+. Run through `tests/Invoke-Tests.ps1`. `tests/fixtures/smoke.ledger.jsonl` is a copy of a
  Claude.Agent smoke ledger; the other fixtures come from `tests/fixtures/New-Fixtures.ps1`.
- `docs/design.md` numbered decisions. Add an entry when you make a decision someone could reasonably reverse.
- `.claude/skills/`: `readme` (this repo's), `ledger-writer` (copied from Claude.Agent.Policy), `git-guard`,
  `run-report` and `graph-node` (copied from Graph HEAD; `tests/Skills.Tests.ps1`). Copies are read-only here; recopy,
  do not edit.

## Commands

- `Invoke-Build` runs the Pester task (default).
- Run Pester only as `pwsh -NoProfile -File tests/Invoke-Tests.ps1`. Multi-line checks go in a temp `.ps1` run with `-File`.

## Rules

- Read only. No code path writes a ledger or spool, or reads `key.bin` (Pester greps for it). Never bake this
  module into the agent image or run it on the agent's network.
- Edit and stage only; no commit, push or tag.
- Ids: `alert:` and `ledger:` only, shapes in design 6. A new prefix is proposed to Graph.Node's `schemas/ids.md` first.
- Every Kind and edge Kind emitted is declared in `ontology.yaml`; keep its `version` equal to `ModuleVersion`.
- Keep the module dependency-free apart from GraphNode, which only `Export-LedgerAlert` loads.
