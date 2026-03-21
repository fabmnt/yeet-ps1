$content = "line1`n`$env:OPENROUTER_API_KEY = 'old'`nline3"
Write-Host "Match without (?m): $($content -match '^\s*\$env:OPENROUTER_API_KEY\s*=')"
Write-Host "Match with (?m): $($content -match '(?m)^\s*\$env:OPENROUTER_API_KEY\s*=')"

$replaced = $content -replace '^\s*\$env:OPENROUTER_API_KEY\s*=.*$', "`$env:OPENROUTER_API_KEY = 'new'"
Write-Host "Replaced without (?m):`n$replaced"

$replaced2 = $content -replace '(?m)^\s*\$env:OPENROUTER_API_KEY\s*=.*$', "`$env:OPENROUTER_API_KEY = 'new'"
Write-Host "Replaced with (?m):`n$replaced2"
