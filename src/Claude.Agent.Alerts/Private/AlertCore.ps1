# Shared helpers for Claude.Agent.Alerts. Not exported.

$script:ModuleRoot = Split-Path -Parent $PSScriptRoot
$script:DefaultRulesPath = Join-Path $script:ModuleRoot 'rules/default.yaml'
$script:OntologyPath = Join-Path $script:ModuleRoot 'ontology.yaml'
$script:Severities = 'info', 'warn', 'error'
$script:SeqGapKind = 'seq-gap'
$script:RuleNamePattern = '^[a-z][a-z0-9-]*$'
$script:WhenKindPattern = '^[A-Za-z][A-Za-z0-9_.-]*$'
$script:FieldPattern = '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*$'

# --- YAML: the block subset the rules file uses (maps, lists, plain and quoted scalars). Flow style throws.

function Remove-YamlComment {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Line)

    $quote = [char]0
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($quote) { if ($c -eq $quote) { $quote = [char]0 } }
        elseif ($c -eq "'" -or $c -eq '"') { $quote = $c }
        elseif ($c -eq '#' -and ($i -eq 0 -or [char]::IsWhiteSpace($Line[$i - 1]))) { return $Line.Substring(0, $i) }
    }
    $Line
}

function ConvertFrom-YamlScalar {
    param([Parameter(Mandatory)][string] $Text, [int] $LineNo)

    $t = $Text.Trim()
    if ($t.StartsWith("'")) {
        if ($t.Length -lt 2 -or -not $t.EndsWith("'")) { throw "line ${LineNo}: unterminated single-quoted scalar" }
        return $t.Substring(1, $t.Length - 2).Replace("''", "'")
    }
    if ($t.StartsWith('"')) {
        if ($t.Length -lt 2 -or -not $t.EndsWith('"')) { throw "line ${LineNo}: unterminated double-quoted scalar" }
        return [regex]::Replace($t.Substring(1, $t.Length - 2), '\\(.)', {
                param($m)
                switch ($m.Groups[1].Value) { 'n' { "`n" } 't' { "`t" } default { $m.Groups[1].Value } }
            })
    }
    if ($t.StartsWith('{') -or $t.StartsWith('[')) { throw "line ${LineNo}: flow style ({...} or [...]) is not supported; use block style" }
    if ($t -in '~', 'null') { return $null }
    $t
}

function Read-YamlNode {
    param([System.Collections.Generic.List[object]] $Lines, [ref] $Index, [int] $Indent)

    $isList = $Lines[$Index.Value].Text -match '^-(\s|$)'
    if ($isList) {
        $list = [System.Collections.Generic.List[object]]::new()
        while ($Index.Value -lt $Lines.Count -and $Lines[$Index.Value].Indent -eq $Indent -and $Lines[$Index.Value].Text -match '^-(\s|$)') {
            $line = $Lines[$Index.Value]
            $rest = $line.Text.Substring(1).TrimStart()
            if ($rest.Length -eq 0) {
                $Index.Value++
                if ($Index.Value -ge $Lines.Count -or $Lines[$Index.Value].Indent -le $Indent) { $list.Add($null); continue }
                $list.Add((Read-YamlNode -Lines $Lines -Index $Index -Indent $Lines[$Index.Value].Indent))
            }
            elseif ($rest -match '^[^''"\s][^:]*:(\s|$)') {
                # "- key: value" opens a map whose keys sit at the column of "key".
                $column = $Indent + ($line.Text.Length - $rest.Length)
                $Lines[$Index.Value] = [pscustomobject]@{ Indent = $column; Text = $rest; No = $line.No }
                $list.Add((Read-YamlNode -Lines $Lines -Index $Index -Indent $column))
            }
            else {
                $list.Add((ConvertFrom-YamlScalar -Text $rest -LineNo $line.No))
                $Index.Value++
            }
        }
        if ($Index.Value -lt $Lines.Count -and $Lines[$Index.Value].Indent -gt $Indent) {
            throw "line $($Lines[$Index.Value].No): unexpected indentation"
        }
        return , $list.ToArray()
    }

    $map = [ordered]@{}
    while ($Index.Value -lt $Lines.Count -and $Lines[$Index.Value].Indent -eq $Indent) {
        $line = $Lines[$Index.Value]
        if ($line.Text -match '^-(\s|$)') { throw "line $($line.No): a list item where a key was expected" }
        $m = [regex]::Match($line.Text, '^(?<k>[^''"\s][^:]*?)\s*:(\s+(?<v>.*))?$')
        if (-not $m.Success) { throw "line $($line.No): expected 'key: value'" }
        $key = $m.Groups['k'].Value
        if ($map.Contains($key)) { throw "line $($line.No): duplicate key '$key'" }
        $Index.Value++
        if ($m.Groups['v'].Success -and $m.Groups['v'].Value.Trim().Length -gt 0) {
            $map[$key] = ConvertFrom-YamlScalar -Text $m.Groups['v'].Value -LineNo $line.No
        }
        elseif ($Index.Value -lt $Lines.Count -and ($Lines[$Index.Value].Indent -gt $Indent -or
                ($Lines[$Index.Value].Indent -eq $Indent -and $Lines[$Index.Value].Text -match '^-(\s|$)'))) {
            $map[$key] = Read-YamlNode -Lines $Lines -Index $Index -Indent $Lines[$Index.Value].Indent
        }
        else {
            $map[$key] = $null
        }
    }
    if ($Index.Value -lt $Lines.Count -and $Lines[$Index.Value].Indent -gt $Indent) {
        throw "line $($Lines[$Index.Value].No): unexpected indentation"
    }
    $map
}

function ConvertFrom-AlertYaml {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $lines = [System.Collections.Generic.List[object]]::new()
    $no = 0
    foreach ($raw in ($Text -split "`r?`n")) {
        $no++
        if ($raw -match '^\s*\t') { throw "line ${no}: tab indentation" }
        $body = (Remove-YamlComment -Line $raw).TrimEnd()
        if ($body.Trim().Length -eq 0 -or $body.Trim() -eq '---') { continue }
        $text = $body.TrimStart()
        $lines.Add([pscustomobject]@{ Indent = $body.Length - $text.Length; Text = $text; No = $no })
    }
    if ($lines.Count -eq 0) { return $null }
    $index = 0
    $node = Read-YamlNode -Lines $lines -Index ([ref]$index) -Indent $lines[0].Indent
    if ($index -lt $lines.Count) { throw "line $($lines[$index].No): unexpected indentation" }
    $node
}

# --- Rules

# Every problem with a parsed rules document, as strings; empty when it is valid.
function Get-AlertRuleProblem {
    param($Document)

    $problems = [System.Collections.Generic.List[string]]::new()
    if ($Document -isnot [System.Collections.IDictionary]) { $problems.Add("the file must be a map with a 'rules' list"); return , $problems.ToArray() }
    foreach ($k in $Document.Keys) { if ($k -ne 'rules') { $problems.Add("unknown top-level key '$k'") } }
    $rules = $Document['rules']
    if ($rules -isnot [array] -or $rules.Count -eq 0) { $problems.Add("'rules' must be a non-empty list"); return , $problems.ToArray() }

    $names = @{}
    for ($i = 0; $i -lt $rules.Count; $i++) {
        $r = $rules[$i]
        $at = "rules[$i]"
        if ($r -isnot [System.Collections.IDictionary]) { $problems.Add("${at}: must be a map"); continue }
        if ($r['name'] -is [string]) { $at = "rules[$i] ($($r['name']))" }
        foreach ($k in $r.Keys) { if ($k -notin 'name', 'when', 'severity', 'message') { $problems.Add("${at}: unknown key '$k'") } }

        $name = $r['name']
        if ($name -isnot [string] -or $name -cnotmatch $script:RuleNamePattern) {
            $problems.Add("${at}: name must match $($script:RuleNamePattern)")
        }
        elseif ($names.ContainsKey($name)) { $problems.Add("${at}: name '$name' is used by rules[$($names[$name])] too") }
        else { $names[$name] = $i }

        $when = $r['when']
        if ($when -isnot [System.Collections.IDictionary]) { $problems.Add("${at}: when must be a map with kind") }
        else {
            foreach ($k in $when.Keys) { if ($k -notin 'kind', 'field', 'match') { $problems.Add("${at}: unknown key 'when.$k'") } }
            if ($when['kind'] -isnot [string] -or $when['kind'] -cnotmatch $script:WhenKindPattern) {
                $problems.Add("${at}: when.kind must be a ledger kind, a Kind.action or seq-gap")
            }
            if ($when.Contains('field') -and ($when['field'] -isnot [string] -or $when['field'] -cnotmatch $script:FieldPattern)) {
                $problems.Add("${at}: when.field must be a dotted path such as body.command")
            }
            if ($when.Contains('match')) {
                if ($when['match'] -isnot [string] -or $when['match'].Length -eq 0) { $problems.Add("${at}: when.match must be a non-empty regex") }
                else {
                    try { [void][regex]::new($when['match']) }
                    catch { $problems.Add("${at}: when.match is not a valid regex: $($_.Exception.InnerException.Message)") }
                }
                if (-not $when.Contains('field')) { $problems.Add("${at}: when.match needs when.field") }
            }
            if ($when['kind'] -ceq $script:SeqGapKind -and $when.Contains('field')) {
                $problems.Add("${at}: a seq-gap rule has no entry of its own to match a field against")
            }
        }

        if ($r['severity'] -notin $script:Severities -or $r['severity'] -isnot [string]) {
            $problems.Add("${at}: severity must be one of $($script:Severities -join ', ')")
        }
        if ($r['message'] -isnot [string] -or $r['message'].Trim().Length -eq 0) { $problems.Add("${at}: message must be a non-empty string") }
    }
    , $problems.ToArray()
}

# Reads and parses a rules file; throws on a parse error or an invalid rule, listing every problem.
function Read-AlertRuleFile {
    param([Parameter(Mandatory)][string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Rules file not found at '$Path'." }
    try { $doc = ConvertFrom-AlertYaml -Text ([System.IO.File]::ReadAllText($Path)) }
    catch { throw "Rules file '$Path' is not valid YAML: $($_.Exception.Message)" }
    $problems = Get-AlertRuleProblem -Document $doc
    if ($problems.Count) { throw "Rules file '$Path' is invalid: $($problems -join '; ')" }

    foreach ($r in $doc['rules']) {
        [pscustomobject]@{
            Name       = $r['name']
            Kind       = $r['when']['kind']
            Field      = $r['when']['field']
            Match      = if ($r['when']['match']) { [regex]::new($r['when']['match']) } else { $null }
            Severity   = $r['severity']
            Message    = $r['message']
            SeqGap     = $r['when']['kind'] -ceq $script:SeqGapKind
            KindAction = $r['when']['kind'] -cmatch '^[A-Z]'
        }
    }
}

# --- Ledger reading (read-only; no key, no chain check)

function Resolve-AlertLedgerFile {
    param([Parameter(Mandatory)][string] $Path)

    $full = [System.IO.Path]::GetFullPath($Path)
    $file = if (Test-Path -LiteralPath $full -PathType Container) { Join-Path $full 'ledger.jsonl' } else { $full }
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Ledger not found at '$file'." }
    $file
}

function ConvertFrom-AlertJson {
    param([Parameter(Mandatory)][string] $Json)

    # Keep stamps as the strings the ledger holds; -DateKind exists from PowerShell 7.5.
    if ($script:JsonDateKind) { $Json | ConvertFrom-Json -AsHashtable -DateKind String -ErrorAction Stop }
    else { $Json | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
}
$script:JsonDateKind = (Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')

# One record per line: Line (1-based), Seq (or $null), Entry (hashtable, or $null when the line is not a JSON object).
function Read-AlertLedger {
    param([Parameter(Mandatory)][string] $File)

    $text = [System.IO.File]::ReadAllText($File, [System.Text.UTF8Encoding]::new($false))
    if ($text.Length -eq 0) { return }
    # A well-formed ledger ends with a newline, which leaves one empty trailing element.
    $lines = $text.TrimEnd("`n") -split "`n"
    $n = 0
    foreach ($line in $lines) {
        $n++
        $entry = $null
        try { $entry = ConvertFrom-AlertJson -Json $line } catch { $entry = $null }
        if ($entry -isnot [System.Collections.IDictionary]) { $entry = $null }
        $seq = $null
        if ($entry -and $entry.Contains('seq') -and ($entry['seq'] -is [long] -or $entry['seq'] -is [int])) { $seq = [long]$entry['seq'] }
        [pscustomobject]@{ Line = $n; Seq = $seq; Entry = $entry }
    }
}

# Test-Ledger's seq rule (Claude.Agent.Ledger design 4) without the key: writer lines must carry seq 1, 2, 3, ...;
# a line whose seq is not the previous seq + 1 is a gap, and counting resumes from its seq. Lines without seq
# (ledger.rejected, 0.1.0 lines, unparseable lines) are not counted.
function Get-AlertSeqGap {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Records)

    $last = 0L
    foreach ($r in $Records) {
        if ($null -eq $r.Seq) { continue }
        if ($r.Seq -ne $last + 1) {
            [pscustomobject]@{ Record = $r; Expected = $last + 1; Found = $r.Seq }
        }
        $last = $r.Seq
    }
}

function Get-AlertField {
    param([System.Collections.IDictionary] $Entry, [string] $Field)

    $value = $Entry
    foreach ($part in $Field.Split('.')) {
        if ($value -isnot [System.Collections.IDictionary] -or -not $value.Contains($part)) { return $null }
        $value = $value[$part]
    }
    $value
}

function ConvertTo-AlertText {
    param($Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [System.IFormattable]) { return $Value.ToString($null, [Globalization.CultureInfo]::InvariantCulture) }
    $Value | ConvertTo-Json -Compress -Depth 32
}

function Get-AlertLedgerId {
    param([Parameter(Mandatory)] $Record)

    if ($null -ne $Record.Seq) { "ledger:$($Record.Seq)" } else { "ledger:line-$($Record.Line)" }
}

function Test-AlertRuleMatch {
    param([Parameter(Mandatory)] $Rule, [Parameter(Mandatory)][System.Collections.IDictionary] $Entry)

    if ($Rule.SeqGap) { return $false }
    $kind = [string]$Entry['kind']
    if ($Rule.KindAction) {
        if (-not $kind.StartsWith('policy.')) { return $false }
        if ([string](Get-AlertField -Entry $Entry -Field 'body.kindAction') -cne $Rule.Kind) { return $false }
    }
    elseif ($kind -cne $Rule.Kind) { return $false }

    if (-not $Rule.Field) { return $true }
    $text = ConvertTo-AlertText (Get-AlertField -Entry $Entry -Field $Rule.Field)
    if ($null -eq $text) { return $false }
    if ($Rule.Match) { return $Rule.Match.IsMatch($text) }
    $text.Length -gt 0
}

function New-AlertFinding {
    param([Parameter(Mandatory)] $Rule, [Parameter(Mandatory)] $Record, [string] $Detail)

    $entry = $Record.Entry
    $body = if ($entry -and $entry['body'] -is [System.Collections.IDictionary]) { $entry['body'] } else { @{} }
    $ledgerId = Get-AlertLedgerId -Record $Record
    $finding = [pscustomobject]@{
        PSTypeName = 'Claude.Agent.Alerts.Finding'
        id         = "alert:$($Rule.Name):$($ledgerId.Substring('ledger:'.Length))"
        rule       = $Rule.Name
        severity   = $Rule.Severity
        message    = $Rule.Message
        detail     = $Detail
        ledgerId   = $ledgerId
        seq        = $Record.Seq
        line       = $Record.Line
        kind       = if ($entry) { $entry['kind'] } else { $null }
        stamp      = if ($entry) { $entry['stamp'] } else { $null }
        phase      = $body['phase']
        tool       = $body['tool']
        kindAction = $body['kindAction']
        path       = $body['path']
        command    = $body['command']
        entry      = $entry
    }
    $finding
}
