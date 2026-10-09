function Invoke-LedgerAlert {
    <#
    .SYNOPSIS
    Reads a ledger and returns one finding per (rule, entry) the rules match, in ledger order.
    .DESCRIPTION
    Read-only: opens ledger.jsonl for reading, never needs or reads key.bin, never writes (design 1). It does not
    check prev or mac; Test-Ledger does that with the key.

    -LedgerPath is the ledger directory or the ledger.jsonl file. -Rules is a rules file (default: the module's
    rules/default.yaml), checked as Test-AlertRule checks it.

    Matching (design 3): post-phase policy.allow and policy.witness entries are the second half of a call the
    pre entry already decided, and are skipped; a post-phase policy.deny is kept (a denied call ran). A seq-gap
    rule fires on the line where the writer's seq breaks, by Test-Ledger's rule, walked over the whole file.

    -FromSeq limits findings to the line whose seq is the first at or above it, and every line after it.
    #>
    [CmdletBinding()]
    [OutputType('Claude.Agent.Alerts.Finding')]
    param(
        [Parameter(Mandatory)][string] $LedgerPath,
        [string] $Rules = $script:DefaultRulesPath,
        [Nullable[long]] $FromSeq
    )

    $ruleSet = @(Read-AlertRuleFile -Path $Rules)
    $file = Resolve-AlertLedgerFile -Path $LedgerPath
    $records = @(Read-AlertLedger -File $file)

    $first = 0
    if ($null -ne $FromSeq) {
        $first = $records.Count
        for ($i = 0; $i -lt $records.Count; $i++) {
            if ($null -ne $records[$i].Seq -and $records[$i].Seq -ge $FromSeq) { $first = $i; break }
        }
    }
    $firstLine = if ($first -lt $records.Count) { $records[$first].Line } else { [long]::MaxValue }

    $gaps = @{}
    foreach ($gap in (Get-AlertSeqGap -Records $records)) {
        if ($gap.Record.Line -ge $firstLine) { $gaps[$gap.Record.Line] = $gap }
    }

    for ($i = $first; $i -lt $records.Count; $i++) {
        $record = $records[$i]
        $entry = $record.Entry
        if (-not $entry) { Write-Warning "ledger line $($record.Line) is not a JSON object; no rule can match it" }
        $skip = $entry -and ([string]$entry['kind']).StartsWith('policy.') -and $entry['kind'] -ne 'policy.deny' -and
            $entry['body'] -is [System.Collections.IDictionary] -and $entry['body']['phase'] -eq 'post'
        foreach ($rule in $ruleSet) {
            if ($rule.SeqGap) {
                $gap = $gaps[$record.Line]
                if ($gap) { New-AlertFinding -Rule $rule -Record $record -Detail "expected seq $($gap.Expected), found $($gap.Found)" }
            }
            elseif ($entry -and -not $skip -and (Test-AlertRuleMatch -Rule $rule -Entry $entry)) {
                $detail = if ($rule.Field) { "$($rule.Field) = $(ConvertTo-AlertText (Get-AlertField -Entry $entry -Field $rule.Field))" } else { $null }
                New-AlertFinding -Rule $rule -Record $record -Detail $detail
            }
        }
    }
}
