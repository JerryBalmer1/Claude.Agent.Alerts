BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:HasGraphNode = Test-Path -LiteralPath $GraphNodeManifest
    if ($HasGraphNode) { Import-Module $GraphNodeManifest -Force }
    $script:Cli = Get-GraphNodeCli
    $script:Layer = [datetime]::new(2026, 10, 9, 1, 14, 45, [DateTimeKind]::Utc)
}

Describe 'Export-LedgerAlert' {
    BeforeEach {
        if (-not $HasGraphNode) { Set-ItResult -Skipped -Because "Graph.Node is not checked out at $GraphNodeManifest" }
    }

    It 'writes <utcStamp>.graph.json with Finding and LedgerEntry nodes and raised-by edges' {
        $ledger = Join-Path $Fixtures 'rules.ledger.jsonl'
        $out = Join-Path $TestDrive 'alerts'
        $file = Invoke-LedgerAlert -LedgerPath $ledger | Export-LedgerAlert -OutDir $out -Layer $Layer -LedgerPath $ledger
        $file.Name | Should -Be '20261009T011445Z.graph.json'
        Join-Path $out 'ontology.yaml' | Should -Exist

        $g = Get-Content $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        $g.schema | Should -Be 'graph/1'
        $g.module | Should -Be 'Claude.Agent.Alerts'
        $g.version | Should -Be '0.1.0'
        $g.ontology | Should -Be 'ontology.yaml'
        $g.root | Should -Be ([System.IO.Path]::GetFullPath($ledger))
        @($g.nodes | Where-Object kind -eq 'Finding') | Should -HaveCount 7
        # seq 10 raised two findings and seq 13 two: one LedgerEntry each.
        @($g.nodes | Where-Object kind -eq 'LedgerEntry').id | Should -Be @('ledger:7', 'ledger:8', 'ledger:10', 'ledger:line-12', 'ledger:13')
        $g.counts.nodes | Should -Be 12
        $g.counts.edges | Should -Be 7
        foreach ($n in $g.nodes) {
            if ($n.kind -eq 'Finding') { $n.id | Should -Match '^alert:' } else { $n.id | Should -Match '^ledger:' }
        }
        foreach ($e in $g.edges) {
            $e.kind | Should -Be 'raised-by'
            $e.from | Should -Match '^alert:'
            $e.to | Should -Match '^ledger:'
        }
        $deny = $g.nodes | Where-Object id -eq 'alert:policy-deny:7'
        $deny.properties.severity | Should -Be 'error'
        $deny.properties.ledgerSeq | Should -Be 7
        ($g.nodes | Where-Object id -eq 'ledger:7').properties.body.command | Should -Be 'rm /work/policy-smoke.txt'
    }

    It 'validates with Test-Graph and with cmd/graphnode validate' {
        $file = Invoke-LedgerAlert -LedgerPath (Join-Path $Fixtures 'rules.ledger.jsonl') | Export-LedgerAlert -OutDir (Join-Path $TestDrive 'v') -Layer $Layer
        (Test-Graph -Path $file.FullName).Valid | Should -BeTrue
        if (-not $Cli) { Set-ItResult -Inconclusive -Because 'no graphnode binary in Graph.Node and no go to run cmd/graphnode'; return }
        $output = & $Cli @('validate', $file.FullName)
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        ($output -join '').Trim() | Should -Be '[]'
    }

    It 'the shipped ontology.yaml validates with cmd/graphnode validate-ontology' {
        if (-not $Cli) { Set-ItResult -Inconclusive -Because 'no graphnode binary in Graph.Node and no go to run cmd/graphnode'; return }
        $output = & $Cli @('validate-ontology', (Join-Path $ModuleRoot 'ontology.yaml'))
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }

    It 'writes a valid empty layer for no findings' {
        $file = Export-LedgerAlert -Findings @() -OutDir (Join-Path $TestDrive 'empty') -Layer $Layer
        $g = Get-Content $file.FullName -Raw | ConvertFrom-Json -AsHashtable
        $g.counts.nodes | Should -Be 0
        $g.counts.edges | Should -Be 0
        if ($Cli) { & $Cli @('validate', $file.FullName) | Out-Null; $LASTEXITCODE | Should -Be 0 }
    }
}

Describe 'Export-LedgerAlert without GraphNode' {
    It 'says how to get it' {
        $script = Join-Path $TestDrive 'no-graphnode.ps1'
        Set-Content -LiteralPath $script -Value @"
`$env:PSModulePath = ''
Import-Module '$(Join-Path $ModuleRoot 'Claude.Agent.Alerts.psd1')'
try { Export-LedgerAlert -Findings @() -OutDir '$(Join-Path $TestDrive 'none')'; 'no error' } catch { `$_.Exception.Message }
"@
        $msg = pwsh -NoProfile -File $script
        "$msg" | Should -BeLike '*needs GraphNode*'
    }
}
