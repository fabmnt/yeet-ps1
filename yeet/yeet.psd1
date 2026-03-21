@{
    RootModule = 'yeet.psm1'
    ModuleVersion = '1.2.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Fabian Montoya'
    CompanyName = ''
    Copyright = '(c) 2026 Fabian Montoya. All rights reserved.'
    Description = 'AI-powered Git PR Creator CLI - Generates commit messages, PR titles, and descriptions using AI'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('yeet')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags = @('git', 'github', 'pr', 'pull-request', 'ai', 'openrouter', 'commit')
            ProjectUri = 'https://github.com/fabmnt/yeet-ps1'
            LicenseUri = 'https://github.com/fabmnt/yeet-ps1/blob/main/LICENSE'
            ReleaseNotes = 'v1.2.0 - Added -Version parameter to show current version'
        }
    }
}
