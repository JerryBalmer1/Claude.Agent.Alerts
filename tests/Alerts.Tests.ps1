BeforeAll {
    . (Join-Path $PSScriptRoot 'TestSetup.ps1')
}

Describe 'Test-AlertRule' {
    It 'accepts the shipped rules/default.yaml' {
        Test-AlertRule | Should -BeTrue
        Test-AlertRule -Path (Join-Path $ModuleRoot 'rules/default.yaml') | Should -BeTrue
    }

    It 'ships the six rules with their severities' {
        $doc = Get-Content (Join-Path $ModuleRoot 'rules/default.yaml') -Raw
        foreach ($pair in 'policy-deny:error', 'seq-gap:error', 'policy-witness:warn', 'shell-network-or-interpreter:warn', 'agent-run-failed:error', 'ledger-rejected:error') {
            $name, $severity = $pair -split ':'
            $doc | Should -Match "(?ms)- name: $name\s.*?severity: $severity"
        }
    }

    It 'lists every problem in one error' {
        $path = New-RulesFile @'
rules:
  - name: Bad_Name
    when:
      kind: policy.deny
      match: '('
      extra: x
    severity: critical
  - name: dup
    when: { kind: x }
    severity: info
    message: m
'@
        { Test-AlertRule -Path $path } | Should -Throw -ExpectedMessage '*flow style*'

        $path = New-RulesFile @'
rules:
  - name: Bad_Name
    when:
      kind: policy.deny
      match: '('
      extra: x
    severity: critical
  - name: dup
    when:
      kind: x
    severity: info
    message: m
  - name: dup
    when:
      kind: seq-gap
      field: body.x
    severity: warn
    message: m
    colour: red
'@
        $err = { Test-AlertRule -Path $path } | Should -Throw -PassThru
        $msg = $err.Exception.Message
        foreach ($expected in 'name must match', "unknown key 'when.extra'", 'when.match is not a valid regex', 'when.match needs when.field',
            'severity must be one of info, warn, error', 'message must be a non-empty string', "name 'dup' is used by rules[1] too",
            "unknown key 'colour'", 'a seq-gap rule has no entry of its own') {
            $msg.Contains($expected) | Should -BeTrue -Because "the error should say: $expected"
        }
    }

    It 'rejects a file without a rules list, and a missing file' {
        { Test-AlertRule -Path (New-RulesFile "rule:`n  - name: x`n") } | Should -Throw -ExpectedMessage "*unknown top-level key 'rule'*"
        { Test-AlertRule -Path (Join-Path $TestDrive 'nope.yaml') } | Should -Throw -ExpectedMessage '*not found*'
    }

    It 'reads quoted scalars and comments as YAML does' {
        $path = New-RulesFile @'
# comment
rules:
  - name: quoted   # trailing comment
    when:
      kind: "policy.deny"
      field: body.command
      match: 'it''s # not a comment'
    severity: info
    message: "a \"quoted\" message"
'@
        Test-AlertRule -Path $path | Should -BeTrue
        $ledger = New-RawLedger 'q.jsonl' @(@{ kind = 'policy.deny'; seq = 1; body = @{ phase = 'pre'; command = "echo it's # not a comment" } })
        $f = @(Invoke-LedgerAlert -LedgerPath $ledger -Rules $path)
        $f | Should -HaveCount 1
        $f[0].message | Should -Be 'a "quoted" message'
    }
}

Describe 'Invoke-LedgerAlert on the fixtures built from the smoke run' {
    It 'every shipped rule fires on rules.ledger.jsonl' {
        $f = @(Invoke-LedgerAlert -LedgerPath (Join-Path $Fixtures 'rules.ledger.jsonl'))
        $byRule = $f | Group-Object rule -AsHashTable -AsString
        foreach ($rule in 'policy-deny', 'seq-gap', 'policy-witness', 'shell-network-or-interpreter', 'agent-run-failed', 'ledger-rejected') {
            $byRule.Keys | Should -Contain $rule
        }
        @($f.id) | Should -Be @(
            'alert:policy-deny:7', 'alert:policy-witness:8', 'alert:policy-witness:10', 'alert:shell-network-or-interpreter:10',
            'alert:ledger-rejected:line-12', 'alert:seq-gap:13', 'alert:agent-run-failed:13')
    }

    It 'carries the rule''s severity and message, the entry''s fields and a detail' {
        $f = @(Invoke-LedgerAlert -LedgerPath (Join-Path $Fixtures 'rules.ledger.jsonl'))
        $deny = $f | Where-Object rule -eq 'policy-deny'
        $deny.severity | Should -Be 'error'
        $deny.ledgerId | Should -Be 'ledger:7'
        $deny.kindAction | Should -Be 'File.delete'
        $deny.command | Should -Be 'rm /work/policy-smoke.txt'
        $deny.phase | Should -Be 'pre'
        $shell = $f | Where-Object rule -eq 'shell-network-or-interpreter'
        $shell.severity | Should -Be 'warn'
        $shell.message | Should -Be 'shell could bypass delete classification'
        $shell.detail | Should -BeLike 'body.command = curl *'
        ($f | Where-Object rule -eq 'seq-gap').detail | Should -Be 'expected seq 12, found 13'
        ($f | Where-Object rule -eq 'agent-run-failed').detail | Should -Be 'body.exitCode = 1'
        $rejected = $f | Where-Object rule -eq 'ledger-rejected'
        $rejected.seq | Should -BeNullOrEmpty
        $rejected.line | Should -Be 12
    }

    It 'a clean ledger yields zero error findings' {
        $f = @(Invoke-LedgerAlert -LedgerPath (Join-Path $Fixtures 'clean.ledger.jsonl'))
        @($f | Where-Object severity -eq 'error') | Should -HaveCount 0
        $f | Should -HaveCount 0
    }

    It 'the seq-gap fixture produces exactly one finding' {
        $f = @(Invoke-LedgerAlert -LedgerPath (Join-Path $Fixtures 'seqgap.ledger.jsonl'))
        $f | Should -HaveCount 1
        $f[0].rule | Should -Be 'seq-gap'
        $f[0].id | Should -Be 'alert:seq-gap:5'
    }

    It 'the smoke ledger (two runs) has one policy-deny per run and nothing else' {
        $f = @(Invoke-LedgerAlert -LedgerPath (Join-Path $Fixtures 'smoke.ledger.jsonl'))
        @($f.id) | Should -Be @('alert:policy-deny:7', 'alert:policy-deny:16')
    }

    It '-FromSeq keeps the last run only' {
        $f = @(Invoke-LedgerAlert -LedgerPath (Join-Path $Fixtures 'smoke.ledger.jsonl') -FromSeq 10)
        @($f.id) | Should -Be @('alert:policy-deny:16')
        @(Invoke-LedgerAlert -LedgerPath (Join-Path $Fixtures 'smoke.ledger.jsonl') -FromSeq 99) | Should -HaveCount 0
    }

    It 'takes the ledger directory as well as the file' {
        $dir = Join-Path $TestDrive 'ledgerdir'
        New-Item -ItemType Directory -Path $dir | Out-Null
        Copy-Item (Join-Path $Fixtures 'smoke.ledger.jsonl') (Join-Path $dir 'ledger.jsonl')
        @(Invoke-LedgerAlert -LedgerPath $dir) | Should -HaveCount 2
    }

    It 'never writes the ledger' {
        $copy = Join-Path $TestDrive 'ro.jsonl'
        Copy-Item (Join-Path $Fixtures 'rules.ledger.jsonl') $copy
        $before = (Get-FileHash $copy).Hash
        $stampBefore = (Get-Item $copy).LastWriteTimeUtc
        Invoke-LedgerAlert -LedgerPath $copy | Out-Null
        (Get-FileHash $copy).Hash | Should -Be $before
        (Get-Item $copy).LastWriteTimeUtc | Should -Be $stampBefore
        Get-ChildItem (Split-Path $copy) -Filter 'key.bin' | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-LedgerAlert matching' {
    It 'skips post-phase allow and witness (the call was already decided) but keeps a post-phase deny' {
        $ledger = New-RawLedger 'phase.jsonl' @(
            @{ kind = 'policy.witness'; seq = 1; body = @{ phase = 'pre'; kindAction = 'Shell.exec'; command = 'wget x' } }
            @{ kind = 'policy.witness'; seq = 2; body = @{ phase = 'post'; kindAction = 'Shell.exec'; command = 'wget x' } }
            @{ kind = 'policy.deny'; seq = 3; body = @{ phase = 'post'; kindAction = 'File.delete'; path = '/work/x' } }
        )
        @((Invoke-LedgerAlert -LedgerPath $ledger).id) | Should -Be @('alert:policy-witness:1', 'alert:shell-network-or-interpreter:1', 'alert:policy-deny:3')
    }

    It 'shell rule matches interpreters and fetchers in command position only' -ForEach @(
        @{ Command = 'curl -s https://x'; Fires = $true }
        @{ Command = 'cd /work && wget http://x'; Fires = $true }
        @{ Command = 'echo hi | nc host 80'; Fires = $true }
        @{ Command = 'python3 -c "import os"'; Fires = $true }
        @{ Command = '/usr/bin/python script.py'; Fires = $true }
        @{ Command = 'node -e "1"'; Fires = $true }
        @{ Command = 'pwsh -c Remove-Item x'; Fires = $true }
        @{ Command = 'pwsh -Command "x"'; Fires = $true }
        @{ Command = 'ls -la /work'; Fires = $false }
        @{ Command = 'rsync -nc a b'; Fires = $false }
        @{ Command = 'cat curly.txt'; Fires = $false }
        @{ Command = 'pwsh -File x.ps1'; Fires = $false }
    ) {
        $ledger = New-RawLedger 'shell.jsonl' @(@{ kind = 'policy.witness'; seq = 1; body = @{ phase = 'pre'; kindAction = 'Shell.exec'; command = $Command } })
        $fired = @(Invoke-LedgerAlert -LedgerPath $ledger | Where-Object rule -eq 'shell-network-or-interpreter').Count -eq 1
        $fired | Should -Be $Fires
    }

    It 'a Kind.action rule matches only policy entries with that kindAction' {
        $ledger = New-RawLedger 'ka.jsonl' @(
            @{ kind = 'agent.note'; seq = 1; body = @{ kindAction = 'Shell.exec'; command = 'curl x' } }
            @{ kind = 'policy.allow'; seq = 2; body = @{ phase = 'pre'; kindAction = 'File.read'; command = 'curl x' } }
        )
        @(Invoke-LedgerAlert -LedgerPath $ledger) | Should -HaveCount 0
    }

    It 'agent.run fires on any exitCode but 0, and not when exitCode is missing' {
        $ledger = New-RawLedger 'run.jsonl' @(
            @{ kind = 'agent.run'; seq = 1; body = @{ exitCode = 0 } }
            @{ kind = 'agent.run'; seq = 2; body = @{ exitCode = 2 } }
            @{ kind = 'agent.run'; seq = 3; body = @{ exitCode = -1 } }
            @{ kind = 'agent.run'; seq = 4; body = @{ exitCode = 10 } }
            @{ kind = 'agent.run'; seq = 5; body = @{} }
        )
        @((Invoke-LedgerAlert -LedgerPath $ledger).seq) | Should -Be @(2, 3, 4)
    }

    It 'a field rule without match fires when the field is present and non-empty' {
        $rules = New-RulesFile "rules:`n  - name: has-path`n    when:`n      kind: policy.allow`n      field: body.path`n    severity: info`n    message: m`n"
        $ledger = New-RawLedger 'f.jsonl' @(
            @{ kind = 'policy.allow'; seq = 1; body = @{ phase = 'pre'; path = '/work/a' } }
            @{ kind = 'policy.allow'; seq = 2; body = @{ phase = 'pre'; path = $null } }
            @{ kind = 'policy.allow'; seq = 3; body = @{ phase = 'pre'; path = '' } }
        )
        @((Invoke-LedgerAlert -LedgerPath $ledger -Rules $rules).seq) | Should -Be @(1)
    }

    It 'seq-gap: gaps, repeats and decreases count; lines without seq do not; counting resumes' {
        $ledger = New-RawLedger 'gaps.jsonl' @(
            @{ kind = 'a'; seq = 1 }; @{ kind = 'b'; seq = 3 }; @{ kind = 'c'; seq = 4 }
            @{ kind = 'ledger.rejected'; body = @{ line = 'x' } }
            @{ kind = 'd'; seq = 4 }; @{ kind = 'e'; seq = 2 }; @{ kind = 'f'; seq = 3 }
        )
        $f = @(Invoke-LedgerAlert -LedgerPath $ledger | Where-Object rule -eq 'seq-gap')
        @($f.line) | Should -Be @(2, 5, 6)
        @($f.detail) | Should -Be @('expected seq 2, found 3', 'expected seq 5, found 4', 'expected seq 5, found 2')
    }

    It 'warns about a line that is not JSON and carries on' {
        $ledger = New-RawLedger 'bad.jsonl' @('garbage', @{ kind = 'policy.deny'; seq = 1; body = @{ phase = 'pre' } })
        $f = @(Invoke-LedgerAlert -LedgerPath $ledger -WarningVariable w -WarningAction SilentlyContinue)
        $f | Should -HaveCount 1
        "$w" | Should -BeLike '*line 1*'
    }

    It 'returns nothing for an empty ledger and throws for a missing one' {
        $empty = Join-Path $TestDrive 'empty.jsonl'
        [System.IO.File]::WriteAllText($empty, '')
        @(Invoke-LedgerAlert -LedgerPath $empty) | Should -HaveCount 0
        { Invoke-LedgerAlert -LedgerPath (Join-Path $TestDrive 'missing.jsonl') } | Should -Throw -ExpectedMessage '*Ledger not found*'
    }
}

Describe 'seq-gap agrees with Test-Ledger' {
    It 'finds the same lines Test-Ledger reports as seq-gap, on a ledger the real keeper chained' {
        if (-not (Test-Path -LiteralPath $LedgerManifest)) {
            Set-ItResult -Skipped -Because "Claude.Agent.Ledger is not checked out at $LedgerManifest"
            return
        }
        Import-Module $LedgerManifest -Force
        $spool = Join-Path $TestDrive 'parity/spool'
        $dir = Join-Path $TestDrive 'parity/ledger'
        Start-LedgerKeeper -Spool $spool -Ledger $dir -Once | Out-Null
        $pending = Join-Path $spool 'pending.jsonl'
        1..6 | ForEach-Object { Add-LedgerEntry -Spool $spool -Kind "test.$_" | Out-Null }
        $lines = @(Get-Content -LiteralPath $pending)
        # Drop seq 2 and 5 before the keeper takes them; add a line the keeper rejects.
        [System.IO.File]::WriteAllText($pending, (($lines[0], 'not json', $lines[2], $lines[3], $lines[5]) -join "`n") + "`n")
        Start-LedgerKeeper -Spool $spool -Ledger $dir -Once | Out-Null

        $err = { Test-Ledger -Path $dir } | Should -Throw -PassThru
        $testLedger = @([regex]::Matches($err.Exception.Message, 'line (\d+) \(seq-gap\)') | ForEach-Object { [int]$_.Groups[1].Value })
        $alerts = @(Invoke-LedgerAlert -LedgerPath $dir | Where-Object rule -eq 'seq-gap' | ForEach-Object line)
        $testLedger | Should -Be @(3, 5)
        $alerts | Should -Be $testLedger
        Remove-Module Claude.Agent.Ledger
    }
}

Describe 'Get-LedgerAlertSummary' {
    It 'counts by severity (all three keys) and by rule' {
        $s = Invoke-LedgerAlert -LedgerPath (Join-Path $Fixtures 'rules.ledger.jsonl') | Get-LedgerAlertSummary
        $s.total | Should -Be 7
        $s.bySeverity.error | Should -Be 4
        $s.bySeverity.warn | Should -Be 3
        $s.bySeverity.info | Should -Be 0
        $s.byRule['policy-witness'] | Should -Be 2
        @($s.byRule.Keys) | Should -Be @('agent-run-failed', 'ledger-rejected', 'policy-deny', 'policy-witness', 'seq-gap', 'shell-network-or-interpreter')
    }

    It 'is all zeros for no findings' {
        $s = Get-LedgerAlertSummary -Findings @()
        $s.total | Should -Be 0
        @($s.bySeverity.Values) | Should -Be @(0, 0, 0)
        $s.byRule.Count | Should -Be 0
    }
}
