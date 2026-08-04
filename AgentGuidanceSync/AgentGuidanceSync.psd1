@{
    RootModule = 'AgentGuidanceSync.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'e20e5784-ce55-49dc-be7d-a8f0ef648664'
    Author = 'Austin Arlt'
    Copyright = '(c) 2026 Austin Arlt. Licensed under the MIT License.'
    Description = 'Preview-first, cross-platform synchronization of agent guidance files over SSH.'
    PowerShellVersion = '7.2'

    FunctionsToExport = @('Sync-AgentGuidance')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('Codex', 'Claude', 'SSH', 'Configuration', 'PowerShell')
            LicenseUri = 'https://opensource.org/license/mit'
        }
    }
}
