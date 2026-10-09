function Test-AlertRule {
    <#
    .SYNOPSIS
    Checks a rules file. Returns $true, or throws listing every problem.
    .DESCRIPTION
    The file is a map with one key, rules: a non-empty list of {name, when: {kind, field?, match?}, severity,
    message}. name matches ^[a-z][a-z0-9-]*$ and is unique (it becomes part of the Finding node id). when.kind
    is a ledger entry kind, a Kind.action, or seq-gap. when.field is a dotted path; when.match is a .NET regex
    and needs when.field. severity is info, warn or error. Unknown keys are problems.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([string] $Path = $script:DefaultRulesPath)

    Read-AlertRuleFile -Path $Path | Out-Null
    $true
}
