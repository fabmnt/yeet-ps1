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

try {
    Import-Module $modulePath -Force -ErrorAction Stop
} catch {
    Write-Error "Failed to import module from path '$modulePath'. $_"
    exit 1
}

if (-not (Get-Command -Name yeet -ErrorAction SilentlyContinue)) {
    Write-Error "The 'yeet' command was not found after importing module '$modulePath'."
    exit 1
}

$params = @{}
if ($DebugMode) { $params['DebugMode'] = $true }
if ($Merge) { $params['Merge'] = $true }
if ($Update) { $params['Update'] = $true }
if ($New) { $params['New'] = $true }
if ($Push) { $params['Push'] = $true }
if ($Help) { $params['Help'] = $true }

yeet @params
