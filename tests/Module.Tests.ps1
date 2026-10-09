BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
    $script:Manifest = Import-PowerShellDataFile -Path (Join-Path $ModuleRoot 'Claude.Agent.Alerts.psd1')

    function Get-SkillVersion([string] $Name) {
        $skill = Get-Content -LiteralPath (Join-Path $RepoRoot '.claude' 'skills' $Name 'SKILL.md') -Raw
        $front = [regex]::Match($skill, '\A---\r?\n(.*?)\r?\n---', 'Singleline').Groups[1].Value
        [regex]::Match($front, '(?m)^version:\s*(\S+)\s*$').Groups[1].Value
    }
}

Describe 'Module' {
    It 'is version 0.1.1 and needs PowerShell 7.4' {
        $Manifest.ModuleVersion | Should -Be '0.1.1'
        $Manifest.PowerShellVersion | Should -Be '7.4'
    }

    It 'exports exactly the functions the manifest lists, one Public file each' {
        @((Get-Module Claude.Agent.Alerts).ExportedFunctions.Keys | Sort-Object) | Should -Be @($Manifest.FunctionsToExport | Sort-Object)
        @(Get-ChildItem -Path (Join-Path $ModuleRoot 'Public') -Filter '*.ps1' | ForEach-Object BaseName | Sort-Object) | Should -Be @($Manifest.FunctionsToExport | Sort-Object)
    }

    It 'ships its rules and ontology inside the module directory, at the module''s version' {
        Join-Path $ModuleRoot 'rules/default.yaml' | Should -Exist
        Join-Path $ModuleRoot 'ontology.yaml' | Should -Exist
        Get-Content (Join-Path $ModuleRoot 'ontology.yaml') -Raw | Should -Match "(?m)^version: $([regex]::Escape($Manifest.ModuleVersion))\s*$"
    }

    It 'has no code path that writes a ledger or reads its key' {
        $code = (Get-ChildItem -Path $ModuleRoot -Recurse -Filter '*.ps1' | Get-Content -Raw) -join "`n"
        $code | Should -Not -Match '[''"]key\.bin'
        $code | Should -Not -Match 'Add-LedgerEntry|Start-LedgerKeeper|New-Ledger'
        $code | Should -Not -Match 'WriteAll(Text|Bytes|Lines)|AppendAll|Set-Content|Add-Content|Out-File'
    }
}

Describe 'repo skills' {
    It 'readme front-matter version equals this module''s ModuleVersion' {
        Get-SkillVersion 'readme' | Should -Be $Manifest.ModuleVersion -Because 'bump the skill with the module'
    }

    It 'ledger-writer (copied from Claude.Agent.Policy) equals Policy''s copy and Claude.Agent.Ledger''s ModuleVersion' {
        $policyCopy = Join-Path $SiblingRoot 'Claude.Agent.Policy/.claude/skills/ledger-writer/SKILL.md'
        if (-not (Test-Path -LiteralPath $LedgerManifest) -or -not (Test-Path -LiteralPath $policyCopy)) {
            Set-ItResult -Skipped -Because 'Claude.Agent.Ledger or Claude.Agent.Policy is not checked out beside this repo'
            return
        }
        Get-SkillVersion 'ledger-writer' | Should -Be (Import-PowerShellDataFile -Path $LedgerManifest).ModuleVersion -Because 'recopy .claude/skills/ledger-writer from Claude.Agent.Policy when Claude.Agent.Ledger''s version changes'
        (Get-Content (Join-Path $RepoRoot '.claude/skills/ledger-writer/SKILL.md') -Raw) -replace "`r`n", "`n" |
            Should -Be ((Get-Content $policyCopy -Raw) -replace "`r`n", "`n") -Because 'it is a copy; do not edit it here'
    }

    It 'graph-node (copied from Graph.Node) front-matter version equals Graph.Node''s own skill' {
        # Graph.Node pins its skill to its ModuleVersion; the copy here is pinned to that skill (design 6).
        $source = Join-Path $GraphNodeRoot '.claude/skills/graph-node/SKILL.md'
        if (-not (Test-Path -LiteralPath $source)) {
            Set-ItResult -Skipped -Because "Graph.Node is not checked out at $GraphNodeRoot"
            return
        }
        $front = [regex]::Match((Get-Content -LiteralPath $source -Raw), '\A---\r?\n(.*?)\r?\n---', 'Singleline').Groups[1].Value
        Get-SkillVersion 'graph-node' | Should -Be ([regex]::Match($front, '(?m)^version:\s*(\S+)\s*$').Groups[1].Value) -Because 'recopy .claude/skills/graph-node from Graph.Node when its version changes'
    }
}
