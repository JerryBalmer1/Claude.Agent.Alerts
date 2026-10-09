---
name: readme
description: Keep README.md, the usage door to Claude.Agent.Alerts, in step with the code. Use whenever an exported function or its parameters change, the rules format or the shipped rules change, the finding or envelope shape (ids, Kinds, edge, properties) changes, ontology.yaml changes, an Invoke-Build task or requirement changes, or the version changes, and before reporting any task that touched one.
version: 0.1.0
---

# README

Copied from Claude.Agent.Policy's `readme` skill and adapted. `README.md` is for whoever runs alerts over a
Claude.Agent ledger, writes a rule, or mounts the alerts layer in the portal. The decisions behind it live in
`docs/design.md`; README links them, never repeats them.

## When to update it

In the same task as any change to:
- an exported function (psd1 `FunctionsToExport`, `src/Claude.Agent.Alerts/Public/`) or its parameters
- `src/Claude.Agent.Alerts/rules/default.yaml`, or what `Test-AlertRule` accepts
- the finding object's properties, the envelope (`module`, Kinds, edge kind, id prefixes), or `ontology.yaml`
- `.build.ps1` tasks, the PowerShell or Pester minimums, or the sibling repos the tests need
- the psd1 version

## Rules

- Sections stay in this order: what it is (under the title), Rules, Functions, Envelope, How Claude.Agent runs it, Development.
- The Functions table lists exactly the psd1 `FunctionsToExport`, in that order, with exact parameter names.
- The Rules table lists exactly the shipped rules, in file order, with their `when` and severity.
- Examples are ones you ran. Use exact command and parameter names; an output comment is what you saw.
- Dense, plain sentences. No marketing words. A table beats a paragraph.
- `version` above equals the module's `ModuleVersion` (Pester checks). Bump both together.
