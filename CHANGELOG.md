# Changelog

## 0.1.2 - 2026-10-08

- 0.1.2: git-guard hook; run-report 0.2.2; graph-node 0.2.1
- Skills git-guard 0.1.0, run-report 0.2.2 and graph-node 0.2.1 copied from Graph HEAD; git-guard's PreToolUse hook merged into `.claude/settings.json`. `tests/Skills.Tests.ps1` checks each copy's version and full text against `git show HEAD:` in Graph, and the hook's exit codes (0, 0, 2, 2, 2, 2 for git status, git add, git commit, git push, git tag, gh pr merge).
- Skill `readme` at 0.1.2 with the module; `ledger-writer` recopied at Claude.Agent.Ledger 0.2.2 (version only). The Module test that pinned graph-node to Graph.Node's copy is replaced by Skills.Tests (source is Graph).

## 0.1.1 - 2026-10-09

- `alert:` and `ledger:` are registered to Claude.Agent.Alerts in Graph.Node 0.2.1 (design 6); skill `graph-node`
  recopied at 0.2.1; LedgerEntry's display shape is `square` (`round-rectangle` is a 0.1.0 name Graph.Node 0.2.x
  warns about); Pester checks every emitted id against `Test-GraphId` and each envelope with
  `graphnode validate --ontology` (`[]`). No id changed.

## 0.1.0 - 2026-10-08

- `Invoke-LedgerAlert -LedgerPath [-Rules] [-FromSeq]`: findings, in ledger order, from a ledger read without
  the key. Post-phase allow and witness entries are skipped; a post-phase deny is kept (design 3).
- seq-gap by Test-Ledger's rule, keyless; Pester checks it names the same lines as Test-Ledger (design 4).
- `rules/default.yaml`: `policy-deny` error, `seq-gap` error, `policy-witness` warn,
  `shell-network-or-interpreter` warn (`curl|wget|nc|python|node|pwsh -c`), `agent-run-failed` error,
  `ledger-rejected` error. `Test-AlertRule` validates a rules file, listing every problem.
- `Export-LedgerAlert`: `<OutDir>/<utcStamp>.graph.json`, GraphNode envelope, module `Claude.Agent.Alerts`,
  Kinds `Finding` (`alert:`) and `LedgerEntry` (`ledger:`), edge `raised-by`; `ontology.yaml` beside it.
  Prefixes proposed against Graph.Node's `schemas/ids.md` (design 6).
- `Get-LedgerAlertSummary` -> `{total, bySeverity, byRule}`.
- Fixtures from Claude.Agent's smoke ledger, replayed through the real keeper (`tests/fixtures/New-Fixtures.ps1`).
- Skills: `readme`, `ledger-writer` (from Claude.Agent.Policy), `graph-node` (from Graph.Node 0.2.0); Pester
  checks each copy's version.
- Pester: 47 tests.
