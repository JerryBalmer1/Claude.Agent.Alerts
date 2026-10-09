# Design decisions

## 1. Alerts reads, never writes the ledger, and never runs on the agent network

Alerts is a reader on the host side of Claude.Agent. It opens `ledger.jsonl` for reading only, never needs or
reads `key.bin`, never writes the ledger or the spool, and is never baked into the agent image or started on
the `inside` network. Claude.Agent copies it to `build/host-modules/`, which the Dockerfile does not copy and
`.dockerignore` keeps out of the build context. Pester checks the module source for writer, keeper and key
references.

Its output is a GraphNode `graph/1` envelope, so the portal mounts alerts as one more layer beside the
emitters' layers instead of parsing a format of its own.

Why: the ledger is evidence. A reader that could write it, or that ran where the agent can reach it, would
make the evidence depend on the reader. A finding is an opinion about the ledger, so it goes in its own layer.

## 2. Rules are a file, in a small YAML subset, read without a dependency

The rules ship as `src/Claude.Agent.Alerts/rules/default.yaml`, inside the module directory (as Claude.Agent.Policy
ships `policy.defaults.json`), so a copy of the module carries its rules. `-Rules` takes another file.

One rule per entry: `{name, when: {kind, field?, match?}, severity: info|warn|error, message}`. `when.kind` has
three forms:

| Form | Example | Matches |
| --- | --- | --- |
| ledger kind | `policy.deny`, `agent.run`, `ledger.rejected` | entries whose `kind` is exactly that |
| Kind.action (starts upper case) | `Shell.exec` | `policy.*` entries whose `body.kindAction` is that, the language the policy speaks (Claude.Agent.Policy design 1) |
| `seq-gap` | `seq-gap` | the line where the writer's seq breaks (decision 4); takes no field |

`when.field` is a dotted path into the entry (`body.command`); a missing or null field never matches.
`when.match` is a .NET regex tested against the field's value as text (numbers invariant, booleans lower
case). With a field and no match, a present non-empty value matches. `agent.run` with `exitCode != 0` is
therefore `field: body.exitCode, match: '^(?!0$)'`: one matcher, no expression language.

The reader handles block maps, block lists and plain or quoted scalars, and throws on flow style and tabs.
Pulling in powershell-yaml for a six-rule file is not worth a dependency in a module Claude.Agent copies
around; Claude.Agent.Policy made the same call. `Test-AlertRule` lists every problem at once.

`name` is `^[a-z][a-z0-9-]*$` and unique, because it is part of the Finding node id.

## 3. A call is one finding, not two

The policy hooks write a pre entry (the decision) and a post entry (the call ran) for every call that ran.
Alerting on both would double every witness. So post-phase `policy.allow` and `policy.witness` entries are
skipped: the pre entry already raised whatever applies. A post-phase `policy.deny` is kept, because it means a
call the policy refuses actually ran (Claude.Agent.Policy's post hook says nothing should produce one).

Findings come out in ledger order, and per line in rule order. A line can raise several (the `curl` witness
raises `policy-witness` and `shell-network-or-interpreter`).

## 4. seq-gap is Test-Ledger's rule, walked without the key

`Test-Ledger` checks seq together with prev and mac, so it needs `key.bin`, and Claude.Agent deletes the key
on the host right after verifying. Alerts must not need the key (decision 1). So Alerts walks seq itself with
Test-Ledger's rule (Claude.Agent.Ledger design 4): writer lines must run 1, 2, 3, ...; a line whose seq is not
the previous + 1 is a gap, counting resumes from its seq (one lost line, one finding); lines without seq
(`ledger.rejected`, 0.1.0 lines) are not counted. Pester builds a ledger with the real keeper, drops spooled
lines, and requires Alerts to name exactly the lines Test-Ledger reports as `seq-gap`.

Alerts does not check prev or mac. That is Test-Ledger's job, with the key, before Alerts runs.

## 5. -FromSeq windows a ledger that accumulates runs

Claude.Agent's ledger volume keeps every run until `Invoke-Build Clean`. `-FromSeq` starts findings at the
first line whose seq is at or above it; Claude.Agent passes the seq of the last `agent.egress-check`, the same
"last run" Smoke uses. The seq walk still covers the whole file, so a gap at the window's first line is seen
against the line before it.

## 6. The envelope: two Kinds, one edge, registered prefixes

`Export-LedgerAlert` writes one envelope per call, `artifacts/alerts/<yyyyMMddTHHmmssZ>.graph.json`, module
`Claude.Agent.Alerts`, layer the same stamp in GraphNode's form. Kinds and edge are declared in the module's
`ontology.yaml`, copied beside the envelope, which names it.

| Kind | Id | What |
| --- | --- | --- |
| `Finding` | `alert:<rule>:<seq>`, or `alert:<rule>:line-<n>` | one rule matching one entry |
| `LedgerEntry` | `ledger:<seq>`, or `ledger:line-<n>` for a keeper line without seq | an entry that raised at least one finding, with its body |

Edge `raised-by`, Finding to LedgerEntry. Only entries that raised a finding become nodes: the layer is the
alerts, not a copy of the ledger.

Findings are nodes, not GraphNode `findings` entries, so the portal can select, filter and link them like any
node; GraphNode's `findings` stay for problems with a graph. Severity keeps the rules' `warn`, a property, not
GraphNode's finding severity.

Both prefixes are registered in Graph.Node 0.2.1, owner Claude.Agent.Alerts, in `schemas/ids.md`,
`Get-GraphIdPrefix` and `graph/ids.go`. `Test-GraphId`, `graph.ValidID` and `graphnode check-id` check the
shapes:

| Prefix | Owner | Shape |
| --- | --- | --- |
| `alert:` | Claude.Agent.Alerts | `alert:<rule>:<seq>`, or `alert:<rule>:line-<n>` for a ledger line without seq; rule lower case, `^[a-z][a-z0-9-]*$` |
| `ledger:` | Claude.Agent.Alerts | `ledger:<seq>`, or `ledger:line-<n>` for a ledger line without seq |

seq and n are positive integers. The rule name is the rules file's `name`, which `Test-AlertRule` already holds to
the same pattern, so every rule that loads gives conforming ids. Pester exports the fixtures and requires every
id to pass `Test-GraphId`, and each envelope to pass `graphnode validate --ontology` with no problem and no warning.

Ids are stable within one ledger, which is append-only. They are not stable across ledgers: `Invoke-Build
Clean` drops the volume and seq starts at 1 again. The envelope's `root` (the ledger path) and `layer` say which
ledger. `ledger:` belongs to the module that issues it; Claude.Agent.Ledger emits no layer, and a registered
prefix is never moved to another owner once ids have been issued with it (Graph.Node design 14).

## 7. Fixtures are replayed through the real keeper; skills are copies with version checks

`tests/fixtures/smoke.ledger.jsonl` is a verbatim copy of Claude.Agent's `artifacts/ledger/ledger.jsonl` (two
claude -p runs). `tests/fixtures/New-Fixtures.ps1` replays its last run through Claude.Agent.Ledger's writer and
keeper to make `clean`, `seqgap` and `rules` ledgers that are really chained (a dropped spool line, a non-JSON
spool line the keeper rejects), then discards the key. The derived files are checked in, so the tests need
no sibling except for the Test-Ledger parity test and the envelope tests.

Skills: `ledger-writer` is copied from Claude.Agent.Policy and must equal that copy and Claude.Agent.Ledger's
ModuleVersion; `readme` is adapted from Policy's and pinned to this module's version; `graph-node` is copied
from Graph.Node, which pins it to its own ModuleVersion, so the copy is pinned to Graph.Node's skill file.
