# Claude.Agent.Alerts

Reads a Claude.Agent ledger and raises findings: policy denies, seq gaps, witnessed shell calls that could
bypass the delete classifier, failed runs, rejected spool lines. Writes them as a GraphNode `graph/1` layer the
portal can mount. Read-only: it never writes the ledger, never needs `key.bin`, and never runs in the agent
image or on its network ([design 1](docs/design.md)).

Requires PowerShell 7.4+. `Export-LedgerAlert` needs GraphNode (`../Graph.Node/src/GraphNode`).

## Rules

`src/Claude.Agent.Alerts/rules/default.yaml`, one rule per entry: `{name, when: {kind, field?, match?},
severity: info|warn|error, message}`. Format and matching: [design 2 and 3](docs/design.md).

| name | when | severity | message |
| --- | --- | --- | --- |
| `policy-deny` | kind `policy.deny` | error | the policy denied a tool call |
| `seq-gap` | kind `seq-gap` ([design 4](docs/design.md)) | error | seq does not follow the previous writer line; ... |
| `policy-witness` | kind `policy.witness` | warn | a witnessed tool call ran |
| `shell-network-or-interpreter` | kind `Shell.exec`, `body.command` matches `curl`, `wget`, `nc`, `python*`, `node`, `pwsh -c` in command position | warn | shell could bypass delete classification |
| `agent-run-failed` | kind `agent.run`, `body.exitCode` not `0` | error | claude -p exited non-zero |
| `ledger-rejected` | kind `ledger.rejected` | error | the keeper rejected a spooled line |

Post-phase `policy.allow` / `policy.witness` entries are skipped (the pre entry is the call); a post-phase
`policy.deny` is not.

## Functions

| Function | What it does |
| --- | --- |
| `Invoke-LedgerAlert -LedgerPath <dir or ledger.jsonl> [-Rules <yaml>] [-FromSeq <n>]` | Returns findings in ledger order: `{id, rule, severity, message, detail, ledgerId, seq, line, kind, stamp, phase, tool, kindAction, path, command, entry}`. `-FromSeq` starts at the first line with seq at or above it ([design 5](docs/design.md)). |
| `Export-LedgerAlert [-Findings <finding[]>] [-OutDir <dir>] [-Layer <datetime>] [-LedgerPath <path>] [-GraphNodePath <psd1>]` | Writes `<OutDir>/<yyyyMMddTHHmmssZ>.graph.json` (default `artifacts/alerts`) and `ontology.yaml` beside it; returns the file. Takes findings from the pipeline. `-LedgerPath` is recorded as the envelope's `root`. |
| `Get-LedgerAlertSummary [-Findings <finding[]>]` | `{total, bySeverity {info, warn, error}, byRule {<rule>: n}}`. Takes findings from the pipeline. |
| `Test-AlertRule [-Path <yaml>]` | `$true`, or throws listing every problem. Defaults to the shipped rules. |

```powershell
Import-Module ./src/Claude.Agent.Alerts
Invoke-LedgerAlert -LedgerPath tests/fixtures/rules.ledger.jsonl | Format-Table id, severity, detail
# alert:policy-deny:7                   error
# alert:policy-witness:8                warn
# alert:policy-witness:10               warn
# alert:shell-network-or-interpreter:10 warn  body.command = curl -s https://example.com/x -o /work/x
# alert:ledger-rejected:line-12         error
# alert:seq-gap:13                      error expected seq 12, found 13
# alert:agent-run-failed:13             error body.exitCode = 1

Import-Module ../Graph.Node/src/GraphNode/GraphNode.psd1
Invoke-LedgerAlert -LedgerPath tests/fixtures/smoke.ledger.jsonl | Export-LedgerAlert -OutDir artifacts/alerts
```

## Envelope

Module `Claude.Agent.Alerts`, ontology `ontology.yaml` (shipped in the module, copied beside each envelope).
Details and the id prefix registration: [design 6](docs/design.md).

| Kind | Id | Properties |
| --- | --- | --- |
| `Finding` | `alert:<rule>:<seq>` or `alert:<rule>:line-<n>` | `rule`, `severity`, `message`, `ledgerLine`, `ledgerSeq`, `detail` |
| `LedgerEntry` | `ledger:<seq>` or `ledger:line-<n>` | `line`, `seq`, `kind`, `stamp`, `body` |

Edge `raised-by`: Finding to LedgerEntry. Only entries that raised a finding are nodes.

## How Claude.Agent runs it

Claude.Agent's Modules task copies `src/Claude.Agent.Alerts` and GraphNode to `build/host-modules/` (never into
the image). Its Alerts task, after Smoke, runs `Invoke-LedgerAlert` on `artifacts/ledger/ledger.jsonl` from
the last run's `agent.egress-check`, writes the envelope to `artifacts/alerts/`, and adds
`alerts {total, bySeverity, errors[], ...}` to `smoke-report.json`. Its Pester requires exactly one error, the
`policy.deny` of the smoke prompt's delete.

## Development

```powershell
Invoke-Build          # runs Pester via pwsh -NoProfile -File tests/Invoke-Tests.ps1
pwsh -NoProfile -File tests/fixtures/New-Fixtures.ps1   # rebuild derived fixtures from smoke.ledger.jsonl
```

The parity test imports Claude.Agent.Ledger from `../Claude.Agent.Ledger`; the envelope tests import GraphNode
and run `graphnode validate` from `../Graph.Node` (its built binary, else `go run ./cmd/graphnode`). Each is
skipped when its checkout is missing.

See [docs/design.md](docs/design.md) for the decisions behind this.
