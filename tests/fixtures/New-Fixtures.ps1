#Requires -Version 7.4
<#
.SYNOPSIS
Rebuilds the derived ledger fixtures from smoke.ledger.jsonl. Run: pwsh -NoProfile -File tests/fixtures/New-Fixtures.ps1
.DESCRIPTION
smoke.ledger.jsonl is a verbatim copy of Claude.Agent's artifacts/ledger/ledger.jsonl. This replays its last run
(from the last agent.egress-check) through Claude.Agent.Ledger's real writer and keeper (../Claude.Agent.Ledger),
so every derived fixture is a chained ledger Test-Ledger would read, then throws the key away:

- clean.ledger.jsonl   the last run without its policy.deny: no rule fires.
- seqgap.ledger.jsonl  clean, with one spooled line dropped before the keeper took it: exactly one seq-gap.
- rules.ledger.jsonl   the last run, plus one trigger per shipped rule: witnessed Bash `curl` and `ls` (pre and
                       post), agent.run exitCode 1, a non-JSON spool line (ledger.rejected) and a dropped line (seq-gap).
#>
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
Import-Module (Join-Path $here '../../../Claude.Agent.Ledger/src/Claude.Agent.Ledger/Claude.Agent.Ledger.psd1') -Force

$entries = @(Get-Content -LiteralPath (Join-Path $here 'smoke.ledger.jsonl') | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
$start = [array]::FindLastIndex([object[]]$entries, [Predicate[object]] { param($e) $e.kind -eq 'agent.egress-check' })
$lastRun = @($entries[$start..($entries.Count - 1)])

# Builds one ledger from steps: @{Kind; Body} entries, 'drop' (lose the next spooled line), or a raw string line.
function New-FixtureLedger([string] $Name, [object[]] $Steps) {
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "alerts-fixture-$([guid]::NewGuid())"
    $spool = Join-Path $work 'spool'
    $ledger = Join-Path $work 'ledger'
    try {
        Start-LedgerKeeper -Spool $spool -Ledger $ledger -Once | Out-Null
        $pending = Join-Path $spool 'pending.jsonl'
        $dropNext = $false
        foreach ($step in $Steps) {
            if ($step -eq 'drop') { $dropNext = $true; continue }
            if ($step -is [string]) { Add-Content -LiteralPath $pending -Value $step; continue }
            Add-LedgerEntry -Spool $spool -Kind $step.Kind -Body $step.Body | Out-Null
            if ($dropNext) {
                $lines = @(Get-Content -LiteralPath $pending)
                [System.IO.File]::WriteAllText($pending, (($lines | Select-Object -SkipLast 1) -join "`n") + $(if ($lines.Count -gt 1) { "`n" }))
                $dropNext = $false
            }
        }
        Start-LedgerKeeper -Spool $spool -Ledger $ledger -Once | Out-Null
        Copy-Item -LiteralPath (Join-Path $ledger 'ledger.jsonl') -Destination (Join-Path $here $Name) -Force
        Write-Host "$Name : $(@(Get-Content (Join-Path $here $Name)).Count) lines"
    }
    finally { Remove-Item -LiteralPath $work -Recurse -Force }
}

function Step($e) { @{ Kind = $e.kind; Body = [hashtable]$e.body } }
$clean = @($lastRun | Where-Object kind -ne 'policy.deny' | ForEach-Object { Step $_ })

New-FixtureLedger 'clean.ledger.jsonl' $clean
# Drop the post-phase File.read allow (the 4th line): the next line shows the gap.
New-FixtureLedger 'seqgap.ledger.jsonl' (@($clean[0..2]) + 'drop' + @($clean[3..($clean.Count - 1)]))

$witness = {
    param([string] $Phase, [string] $Command)
    $body = @{ phase = $Phase; tool = 'Bash'; kindAction = 'Shell.exec'; path = $null; rule = 'rules[5]'; command = $Command }
    if ($Phase -eq 'pre') { $body.reason = 'Shell.exec witnessed by policy rules[5]' }
    @{ Kind = 'policy.witness'; Body = $body }
}
$rules = foreach ($e in $lastRun) {
    if ($e.kind -eq 'agent.run') {
        & $witness 'pre' 'ls -la /work'
        & $witness 'post' 'ls -la /work'
        & $witness 'pre' 'curl -s https://example.com/x -o /work/x'
        & $witness 'post' 'curl -s https://example.com/x -o /work/x'
        'not json'
        'drop'
        @{ Kind = 'agent.note'; Body = @{ text = 'lost before the keeper took it' } }
        $run = Step $e
        $run.Body.exitCode = 1
        $run.Body.output = 'Error: the run failed'
        $run
    }
    else { Step $e }
}
New-FixtureLedger 'rules.ledger.jsonl' @($rules)
