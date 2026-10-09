# Dot-sourced by each test file's BeforeAll.
$RepoRoot = Split-Path -Parent $PSScriptRoot
$SiblingRoot = Split-Path -Parent $RepoRoot
$ModuleRoot = Join-Path $RepoRoot 'src/Claude.Agent.Alerts'
$Fixtures = Join-Path $PSScriptRoot 'fixtures'
$LedgerManifest = Join-Path $SiblingRoot 'Claude.Agent.Ledger/src/Claude.Agent.Ledger/Claude.Agent.Ledger.psd1'
$GraphNodeRoot = Join-Path $SiblingRoot 'Graph.Node'
$GraphNodeManifest = Join-Path $GraphNodeRoot 'src/GraphNode/GraphNode.psd1'
Import-Module (Join-Path $ModuleRoot 'Claude.Agent.Alerts.psd1') -Force

# Graph.Node's cmd/graphnode: the built binary if there is one, else `go run`, else $null.
function Get-GraphNodeCli {
    $rid = if ($IsWindows) { 'win-x64/graphnode.exe' } else { 'linux-x64/graphnode' }
    $bin = Join-Path $GraphNodeRoot "src/GraphNode/bin/$rid"
    if (Test-Path -LiteralPath $bin) { return { param($a) & $bin @a }.GetNewClosure() }
    if ((Get-Command go -ErrorAction Ignore) -and (Test-Path (Join-Path $GraphNodeRoot 'cmd/graphnode'))) {
        $root = $GraphNodeRoot
        return { param($a) Push-Location $root; try { & go run ./cmd/graphnode @a } finally { Pop-Location } }.GetNewClosure()
    }
    $null
}

# A ledger of raw lines in TestDrive (no chain: Invoke-LedgerAlert never checks prev or mac).
function New-RawLedger([string] $Name, [object[]] $Entries) {
    $path = Join-Path $TestDrive $Name
    $lines = foreach ($e in $Entries) { if ($e -is [string]) { $e } else { $e | ConvertTo-Json -Compress -Depth 8 } }
    [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"))
    $path
}

function New-RulesFile([string] $Text) {
    $path = Join-Path $TestDrive "rules-$([guid]::NewGuid()).yaml"
    [System.IO.File]::WriteAllText($path, $Text)
    $path
}
