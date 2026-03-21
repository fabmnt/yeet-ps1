param(
    [switch]$DebugMode,
    [Alias("m")]
    [switch]$Merge,
    [Alias("u")]
    [switch]$Update,
    [Alias("n")]
    [switch]$New,
    [Alias("p")]
    [switch]$Push,
    [switch]$Version,
    [Alias("h")]
    [switch]$Help,
    [Alias("s")]
    [switch]$Setup
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

if ($Merge) { yeet -Merge } 
elseif ($Update) { 
    if ($New) { yeet -Update -New } 
    else { yeet -Update }
}
elseif ($Push) { yeet -Push }
elseif ($Version) { yeet -Version }
elseif ($Help) { yeet -Help }
elseif ($Setup) { yeet -Setup }
elseif ($DebugMode) { yeet -DebugMode }
else { yeet }
