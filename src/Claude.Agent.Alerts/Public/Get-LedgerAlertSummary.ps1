function Get-LedgerAlertSummary {
    <#
    .SYNOPSIS
    Counts findings: {total, bySeverity {info, warn, error}, byRule {<rule>: n}}.
    .DESCRIPTION
    bySeverity always has all three keys; byRule has only rules that fired, in name order.
    #>
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline)][AllowEmptyCollection()][object[]] $Findings = @())

    begin { $all = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($f in $Findings) { if ($null -ne $f) { $all.Add($f) } } }
    end {
        $bySeverity = [ordered]@{}
        foreach ($s in $script:Severities) { $bySeverity[$s] = @($all | Where-Object severity -eq $s).Count }
        $byRule = [ordered]@{}
        foreach ($g in ($all | Group-Object rule | Sort-Object Name)) { $byRule[$g.Name] = $g.Count }
        [pscustomobject]@{ total = $all.Count; bySeverity = $bySeverity; byRule = $byRule }
    }
}
