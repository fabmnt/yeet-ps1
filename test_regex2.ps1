$content = "`$env:OPENROUTER_API_KEY = 'old'`nline2"
Write-Host "Match: $($content -match '^\s*\$env:OPENROUTER_API_KEY\s*=')"
$replaced = $content -replace '^\s*\$env:OPENROUTER_API_KEY\s*=.*$', "NEW"
Write-Host "Replaced:`n$replaced"
