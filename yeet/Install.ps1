# yeet - AI-powered Git PR Creator CLI
# PowerShell Gallery installation script

$ErrorActionPreference = "Stop"

Write-Host "Installing yeet module..." -ForegroundColor Cyan

$modulePath = Join-Path $env:USERPROFILE "Documents\PowerShell\Modules\yeet"
$repoPath = Split-Path $PSScriptRoot -Parent

if (-not (Test-Path $modulePath)) {
    New-Item -ItemType Directory -Path $modulePath -Force | Out-Null
}

Copy-Item -Path (Join-Path $repoPath "yeet\*") -Destination $modulePath -Recurse -Force

Write-Host "yeet installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "To use yeet, run:" -ForegroundColor Yellow
Write-Host "  Import-Module yeet" -ForegroundColor White
Write-Host "  yeet" -ForegroundColor White
Write-Host ""
Write-Host "Add 'Import-Module yeet' to your profile to auto-load." -ForegroundColor DarkGray
