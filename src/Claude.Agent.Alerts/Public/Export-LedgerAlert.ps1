function Export-LedgerAlert {
    <#
    .SYNOPSIS
    Writes findings as a GraphNode graph/1 envelope, <OutDir>/<utcStamp>.graph.json, and returns the file.
    .DESCRIPTION
    One Finding node per finding (id alert:<rule>:<seq>), one LedgerEntry node per entry that raised a finding
    (id ledger:<seq>, or ledger:line-<n> for a keeper line without seq), and a raised-by edge from each Finding
    to its LedgerEntry. Module Claude.Agent.Alerts, layer = -Layer as a UTC stamp. The module's ontology.yaml is
    copied beside the envelope, which names it. Export-Graph validates the envelope before writing it.

    Needs GraphNode (New-GraphNode, New-GraphEdge, New-GraphEnvelope, Export-Graph): already imported, or
    importable by name, or given as -GraphNodePath (GraphNode.psd1).
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(ValueFromPipeline)][AllowEmptyCollection()][object[]] $Findings = @(),
        [string] $OutDir = 'artifacts/alerts',
        [datetime] $Layer = [datetime]::UtcNow,
        [string] $LedgerPath,
        [string] $GraphNodePath
    )

    begin { $all = [System.Collections.Generic.List[object]]::new() }
    process { foreach ($f in $Findings) { if ($null -ne $f) { $all.Add($f) } } }
    end {
        if (-not (Get-Command New-GraphEnvelope -ErrorAction Ignore)) {
            try { Import-Module $(if ($GraphNodePath) { $GraphNodePath } else { 'GraphNode' }) -ErrorAction Stop }
            catch { throw "Export-LedgerAlert needs GraphNode: Import-Module <Graph.Node checkout>/src/GraphNode/GraphNode.psd1, or pass -GraphNodePath. $($_.Exception.Message)" }
        }

        $utc = $Layer.ToUniversalTime()
        $stamp = $utc.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [Globalization.CultureInfo]::InvariantCulture)
        $entries = [ordered]@{}
        $nodes = [System.Collections.Generic.List[object]]::new()
        $edges = [System.Collections.Generic.List[object]]::new()
        foreach ($f in $all) {
            if (-not $entries.Contains($f.ledgerId)) {
                $props = [ordered]@{ line = $f.line }
                if ($null -ne $f.seq) { $props.seq = $f.seq }
                if ($f.kind) { $props.kind = $f.kind }
                if ($f.stamp) { $props.stamp = [string]$f.stamp }
                if ($f.entry -and $null -ne $f.entry['body']) { $props.body = $f.entry['body'] }
                $label = if ($null -ne $f.seq) { "$($f.seq) $($f.kind)" } else { "line $($f.line) $($f.kind)" }
                $entries[$f.ledgerId] = New-GraphNode -Id $f.ledgerId -Kind LedgerEntry -Name $label.Trim() -Properties $props
            }
            $props = [ordered]@{ rule = $f.rule; severity = $f.severity; message = $f.message; ledgerLine = $f.line }
            if ($null -ne $f.seq) { $props.ledgerSeq = $f.seq }
            if ($f.detail) { $props.detail = $f.detail }
            $node = New-GraphNode -Id $f.id -Kind Finding -Name "$($f.rule) at $($f.ledgerId)" -Properties $props
            $nodes.Add($node)
            $edges.Add((New-GraphEdge -From $node -To $f.ledgerId -Kind raised-by))
        }
        $nodes.AddRange([object[]]@($entries.Values))

        $version = (Import-PowerShellDataFile -Path (Join-Path $script:ModuleRoot 'Claude.Agent.Alerts.psd1')).ModuleVersion
        $envArgs = @{
            Module   = 'Claude.Agent.Alerts'
            Version  = $version
            Layer    = $stamp
            Ontology = 'ontology.yaml'
            Nodes    = $nodes.ToArray()
            Edges    = $edges.ToArray()
        }
        if ($LedgerPath) { $envArgs.Root = Resolve-AlertLedgerFile -Path $LedgerPath }
        $envelope = New-GraphEnvelope @envArgs

        $dir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Copy-Item -LiteralPath $script:OntologyPath -Destination (Join-Path $dir 'ontology.yaml') -Force
        $name = $utc.ToString("yyyyMMdd'T'HHmmss'Z'", [Globalization.CultureInfo]::InvariantCulture) + '.graph.json'
        Export-Graph $envelope -Path (Join-Path $dir $name)
    }
}
