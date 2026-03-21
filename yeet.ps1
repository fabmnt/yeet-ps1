param(
    [switch]$DebugMode,
    [Alias("m")]
    [switch]$Merge,
    [Alias("u")]
    [switch]$Update,
    [Alias("n")]
    [switch]$New,
    [switch]$Push,
    [Alias("h")]
    [switch]$Help
)

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = Join-Path $scriptPath "yeet\yeet.psm1"

if (-not (Test-Path $modulePath)) {
    Write-Error "Module not found at: $modulePath"
    exit 1
}

Import-Module $modulePath -Force

$params = @{}
if ($DebugMode) { $params['DebugMode'] = $true }
if ($Merge) { $params['Merge'] = $true }
if ($Update) { $params['Update'] = $true }
if ($New) { $params['New'] = $true }
if ($Push) { $params['Push'] = $true }
if ($Help) { $params['Help'] = $true }

yeet @params
