# Changelog

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
