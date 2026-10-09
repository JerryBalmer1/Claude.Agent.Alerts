@{
    RootModule           = 'Claude.Agent.Alerts.psm1'
    ModuleVersion        = '0.1.2'
    GUID                 = '3d9c7e15-2a64-4f0b-8e51-6c2b9f4a1d73'
    Author               = 'JerryBalmer1'
    Description          = 'Reads a Claude.Agent ledger and raises findings (policy deny, seq gap, risky shell) as a GraphNode layer.'
    PowerShellVersion    = '7.4'
    CompatiblePSEditions = @('Core')
    FunctionsToExport    = @('Invoke-LedgerAlert', 'Export-LedgerAlert', 'Get-LedgerAlertSummary', 'Test-AlertRule')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{ PSData = @{ Tags = @('ledger', 'alerts', 'graph') } }
}
