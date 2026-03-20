function yeet {
    [CmdletBinding()]
    param(
        [switch]$DebugMode,
        [Alias("m")]
        [switch]$Merge,
        [Alias("u")]
        [switch]$Update,
        [Alias("n")]
        [switch]$New,
        [Alias("h")]
        [switch]$Help
    )

    $ErrorActionPreference = "Stop"

    function Show-Help {
        Write-Host ""
        Write-Host "yeet - Git PR Creator CLI" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Usage: yeet [-DebugMode] [-Merge] [-Update [-New]] [-Help]" -ForegroundColor White
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -DebugMode, -D          Enable debug output" -ForegroundColor White
        Write-Host "  -Merge, -m              Merge an existing PR to base branch" -ForegroundColor White
        Write-Host "  -Update, -u             Update existing PR from current branch changes" -ForegroundColor White
        Write-Host "  -New, -n                With -Update, also refresh PR title/description" -ForegroundColor White
        Write-Host "  -Help, -h               Show this help message" -ForegroundColor White
        Write-Host ""
        Write-Host "Description:" -ForegroundColor Yellow
        Write-Host "  Creates PRs with AI-generated commit messages, titles, and descriptions." -ForegroundColor White
        Write-Host "  With -Merge: merges the current branch PR and updates local base branch." -ForegroundColor White
        Write-Host "  With -Update: commits and pushes uncommitted changes to the open PR branch." -ForegroundColor White
        Write-Host "  With -Update -New: also regenerates and updates open PR title/body." -ForegroundColor White
        Write-Host ""
        return
    }

    if ($Help) {
        Show-Help
        return
    }

    function Debug-Log {
        param([string]$Message)
        if ($DebugMode) {
            Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray
        }
    }

    $profilePath = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
    if (-not $env:OPENROUTER_API_KEY -and (Test-Path $profilePath)) {
        Debug-Log "Loading PowerShell profile from: $profilePath"
        . $profilePath
    }

    $apiKey = $env:OPENROUTER_API_KEY
    if (-not $apiKey) {
        Write-Error "OPENROUTER_API_KEY environment variable is not set"
        return
    }
    Debug-Log "OPENROUTER_API_KEY detected"

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Error "GitHub CLI ('gh') is not installed or not available on PATH. Install it from https://cli.github.com/ and try again."
        return
    }
    Debug-Log "GitHub CLI detected"

    Debug-Log "Checking GitHub CLI authentication status"
    gh auth status 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
        return
    }
    Debug-Log "GitHub CLI authentication verified"

    function Get-GeneratedBranchName {
        param([string]$Title)

        $branchName = ($Title -replace '\s+', '-' -replace '[^a-zA-Z0-9\-]', '' -replace '-{2,}', '-').ToLower().Trim('-')
        if (-not $branchName) {
            $branchName = "update-changes"
        }

        Debug-Log "Generated branch name '$branchName' from title '$Title'"

        return $branchName
    }

    function Get-UntrackedFilePromptSections {
        param(
            [int]$MaxFileChars = 12000,
            [int]$MaxTotalChars = 48000
        )

        $untrackedFiles = git ls-files --others --exclude-standard
        if (-not $untrackedFiles) {
            return @()
        }

        $sections = @()
        $totalChars = 0

        foreach ($file in $untrackedFiles) {
            if (-not (Test-Path $file -PathType Leaf)) {
                continue
            }

            $section = ""
            try {
                $resolvedPath = (Resolve-Path $file).Path
                $bytes = [System.IO.File]::ReadAllBytes($resolvedPath)

                if ($bytes -contains 0) {
                    $section = "=== New untracked file: $file ===`n[binary file omitted]"
                } else {
                    $content = [System.Text.Encoding]::UTF8.GetString($bytes)
                    if ($content.Length -gt $MaxFileChars) {
                        $content = $content.Substring(0, $MaxFileChars) + "`n...[truncated]"
                    }
                    $section = "=== New untracked file: $file ===`n$content"
                }
            } catch {
                $section = "=== New untracked file: $file ===`n[unable to read file: $($_.Exception.Message)]"
            }

            if (($totalChars + $section.Length) -gt $MaxTotalChars) {
                $sections += "=== Additional untracked files omitted due to size limits ==="
                break
            }

            $sections += $section
            $totalChars += $section.Length
        }

        return $sections
    }

    function Invoke-AIRequest {
        param(
            [string]$Diff,
            [bool]$NeedsCommitMessage,
            [bool]$NeedsPrDetails = $true,
            [string]$CurrentPrTitle = "",
            [string]$CurrentPrDescription = ""
        )

        $defaultModel = "nvidia/nemotron-3-super-120b-a12b:free"
        $model = if ($env:OPENROUTER_MODEL_ID) {
            $env:OPENROUTER_MODEL_ID
        } elseif ($env:OPENROUTER_MODEL) {
            $env:OPENROUTER_MODEL
        } else {
            $defaultModel
        }
        $hasCurrentPrContext = -not [string]::IsNullOrWhiteSpace($CurrentPrTitle) -or -not [string]::IsNullOrWhiteSpace($CurrentPrDescription)

        $sections = @()
        if ($NeedsCommitMessage) {
            $sections += "COMMIT: <commit message>"
        }
        if ($NeedsPrDetails) {
            $sections += "TITLE: <pr title>"
            $sections += "DESCRIPTION: <pr description>"
        }
        $formatInstructions = $sections -join " | "

        if ($hasCurrentPrContext) {
            $systemPrompt = @"
Generate a git commit message, PR title, and PR description from the provided diff.

Return your response using this exact format:
$formatInstructions

Rules:
- COMMIT: One line in conventional commits format (max 72 chars), no quotes, no markdown
- TITLE: Brief PR title (40-72 chars), no quotes, no markdown
- DESCRIPTION: Markdown with sections ## Summary, ## Changes (bullet list), ## Notes

When updating an existing PR, make granular edits that preserve the current intent unless the new changes require adjustment.
"@
        } else {
            $systemPrompt = @"
Generate a git commit message, PR title, and PR description from the provided diff.

Return your response using this exact format:
$formatInstructions

Rules:
- COMMIT: One line in conventional commits format (max 72 chars), no quotes, no markdown
- TITLE: Brief PR title (40-72 chars), no quotes, no markdown
- DESCRIPTION: Markdown with sections ## Summary, ## Changes (bullet list), ## Notes
"@
        }

        Debug-Log "Using model: $model"

        $requestInput = "Diff:`n$Diff"
        if ($hasCurrentPrContext) {
            $requestInput += "`n`nCurrent PR title:`n$CurrentPrTitle`n`nCurrent PR description:`n$CurrentPrDescription"
            Debug-Log "Including current PR title/description in AI context for granular updates"
        }

        $lastErrorMessage = ""
        $attempts = 0
        $maxTokens = if ($NeedsPrDetails) { 1400 } else { 150 }

        for ($attempt = 1; $attempt -le 3; $attempt++) {
            $attempts = $attempt

            $loadingJob = Start-Job -ScriptBlock {
                param($apiKey, $model, $systemPrompt, $requestInput, $maxTokens)
                Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/chat/completions" `
                    -Method POST `
                    -Headers @{
                        "Authorization" = "Bearer $apiKey"
                        "Content-Type" = "application/json"
                    } `
                    -Body (@{
                        model = $model
                        messages = @(
                            @{ role = "system"; content = $systemPrompt }
                            @{ role = "user"; content = $requestInput }
                        )
                        max_tokens = $maxTokens
                        reasoning = @{ enabled = $false }
                    } | ConvertTo-Json -Depth 10 -Compress)
            } -ArgumentList $apiKey, $model, $systemPrompt, $requestInput, $maxTokens

            $spinnerChars = @('⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏')
            $startTime = Get-Date

            while ($loadingJob.State -eq 'Running') {
                $elapsed = ((Get-Date) - $startTime).TotalSeconds
                $spinner = $spinnerChars[[int]($elapsed * 30) % $spinnerChars.Count]
                Write-Host "`r$spinner Generating details..." -NoNewline -ForegroundColor Cyan
                Start-Sleep -Milliseconds 33
            }

            Write-Host "`r" + (" " * 60) + "`r" -NoNewline

            try {
                $response = Receive-Job -Job $loadingJob -ErrorAction Stop | Select-Object -First 1
            } finally {
                Remove-Job -Job $loadingJob -Force -ErrorAction SilentlyContinue
            }

            $loadingJob = $null

            try {
                $message = $response.choices[0].message
                $output = ""

                if ($message -and $message.content -is [string]) {
                    $output = $message.content.Trim()
                } elseif ($message -and $message.content -is [System.Collections.IEnumerable]) {
                    $parts = @()
                    foreach ($part in $message.content) {
                        if ($part -is [string]) {
                            $parts += $part
                        } elseif ($part.PSObject.Properties["text"] -and $part.text) {
                            $parts += [string]$part.text
                        }
                    }
                    $output = ($parts -join "`n").Trim()
                } elseif ($response.choices[0].text) {
                    $output = ([string]$response.choices[0].text).Trim()
                }

                if (-not $output) {
                    $lastErrorMessage = "Empty AI response"
                    Write-Host "`r[RETRY] Empty response, retrying ($attempt/3)..." -NoNewline -ForegroundColor Yellow
                    continue
                }

                $commitMessage = $null
                $title = $null
                $description = $null

                $normalizedOutput = ($output -replace "`r", "")
                $lines = $normalizedOutput -split "`n"
                $descriptionLines = New-Object System.Collections.Generic.List[string]
                $collectDescription = $false

                foreach ($rawLine in $lines) {
                    if ($rawLine -match '^\s*```') {
                        continue
                    }

                    $line = $rawLine.TrimEnd()

                    if ($line -match '^\s*(?i:COMMIT)\s*:\s*(.*)$') {
                        if (-not $commitMessage) {
                            $commitMessage = $matches[1].Trim()
                        }
                        $collectDescription = $false
                        continue
                    }

                    if ($line -match '^\s*(?i:TITLE)\s*:\s*(.*)$') {
                        if (-not $title) {
                            $title = $matches[1].Trim()
                        }
                        $collectDescription = $false
                        continue
                    }

                    if ($line -match '^\s*(?i:DESCRIPTION)\s*:\s*(.*)$') {
                        $collectDescription = $true
                        $firstDescriptionLine = $matches[1]
                        if (-not [string]::IsNullOrWhiteSpace($firstDescriptionLine)) {
                            $descriptionLines.Add($firstDescriptionLine.TrimEnd())
                        }
                        continue
                    }

                    if ($collectDescription) {
                        $descriptionLines.Add($rawLine)
                    }
                }

                if ($NeedsCommitMessage -and -not $commitMessage) {
                    if ($normalizedOutput -match '(?is)\bCOMMIT\s*:\s*(.+?)(?=\s*\|\s*\bTITLE\s*:|\s*\+\s*TITLE\s*:|\s*\bTITLE\s*:|\s*\|\s*\bDESCRIPTION\s*:|\s*\+\s*DESCRIPTION\s*:|\s*\bDESCRIPTION\s*:|$)') {
                        $commitMessage = $matches[1].Trim()
                    }
                }

                if ($NeedsPrDetails -and -not $title) {
                    if ($normalizedOutput -match '(?is)\bTITLE\s*:\s*(.+?)(?=\s*\|\s*\bDESCRIPTION\s*:|\s*\+\s*DESCRIPTION\s*:|\s*\bDESCRIPTION\s*:|$)') {
                        $title = $matches[1].Trim()
                    }
                }

                if ($NeedsPrDetails -and $descriptionLines.Count -eq 0) {
                    if ($normalizedOutput -match '(?is)\bDESCRIPTION\s*:\s*(.+)$') {
                        $inlineDescription = $matches[1].Trim()
                        if ($inlineDescription) {
                            $descriptionLines.Add($inlineDescription)
                        }
                    }
                }

                if ($NeedsCommitMessage -and $commitMessage) {
                    $commitMessage = ($commitMessage -replace '^["''`]+|["''`]+$', '').Trim()
                }

                if ($NeedsPrDetails -and $title) {
                    $title = ($title -replace '^["''`]+|["''`]+$', '').Trim()
                }

                if ($NeedsPrDetails) {
                    if ($descriptionLines.Count -gt 0) {
                        $description = ($descriptionLines -join "`n").Trim()
                        if ($description -and $description -match '\\n') {
                            $description = $description -replace '\\n', "`n"
                        }
                    } else {
                        $descriptionFallback = $normalizedOutput -replace '(?im)^\s*(COMMIT|TITLE)\s*:\s*.*$\n?', ''
                        $descriptionFallback = ($descriptionFallback -replace '(?im)^\s*DESCRIPTION\s*:\s*', '').Trim()
                        if ($descriptionFallback) {
                            $description = $descriptionFallback
                            if ($description -match '\\n') {
                                $description = $description -replace '\\n', "`n"
                            }
                        }
                    }
                }

                $valid = $true
                if ($NeedsCommitMessage -and -not $commitMessage) { $valid = $false }
                if ($NeedsPrDetails -and -not $title) { $valid = $false }
                if ($NeedsPrDetails -and -not $description) { $valid = $false }

                if ($valid) {
                    if ($attempt -gt 1) {
                        Write-Host "[RETRY] Succeeded on attempt $attempt" -ForegroundColor Yellow
                    }

                    if ($commitMessage -and $commitMessage.Length -gt 72) {
                        $commitMessage = $commitMessage.Substring(0, 72).Trim()
                    }

                    Debug-Log "Generated commit message length: $(if($commitMessage){$commitMessage.Length}else{0})"
                    if ($NeedsPrDetails) {
                        Debug-Log "Generated title length: $($title.Length)"
                        Debug-Log "Generated description length: $($description.Length)"
                    }

                    return [PSCustomObject]@{
                        'commit-message' = $commitMessage
                        title = $title
                        description = $description
                        attempts = $attempt
                    }
                }

                if ($DebugMode) {
                    $missingFields = @()
                    if ($NeedsCommitMessage -and -not $commitMessage) { $missingFields += "COMMIT" }
                    if ($NeedsPrDetails -and -not $title) { $missingFields += "TITLE" }
                    if ($NeedsPrDetails -and -not $description) { $missingFields += "DESCRIPTION" }
                    $missingText = if ($missingFields.Count -gt 0) { $missingFields -join ", " } else { "unknown" }
                    Debug-Log "Parse error on attempt $attempt. Missing fields: $missingText"

                    $previewLimit = 1200
                    $outputPreview = if ($output.Length -gt $previewLimit) {
                        $output.Substring(0, $previewLimit) + "... [truncated]"
                    } else {
                        $output
                    }
                    Debug-Log "Raw AI output preview:`n$outputPreview"
                }

                $lastErrorMessage = "Failed to parse response: missing fields"
                Write-Host "`r[RETRY] Parse error, retrying ($attempt/3)..." -NoNewline -ForegroundColor Yellow
            } catch {
                $lastErrorMessage = $_.Exception.Message
                Write-Host "`r[RETRY] Error: $($_.Exception.Message), retrying ($attempt/3)..." -NoNewline -ForegroundColor Yellow
            }
        }

        Write-Error "AI request failed after 3 retries: $lastErrorMessage"
        return
    }

    Debug-Log "Starting Git PR Creator"

    $status = git status --porcelain
    $hasUncommittedChanges = $status -ne $null -and $status.Length -gt 0
    Debug-Log "Has uncommitted changes: $hasUncommittedChanges"

    $currentBranch = git branch --show-current
    if (-not $currentBranch) {
        Write-Error "Not on a branch. Please checkout a branch first."
        return
    }
    Debug-Log "Current branch: $currentBranch"

    $defaultBranch = gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
    if (-not $defaultBranch) {
        $defaultBranch = "main"
    }
    Debug-Log "Default branch: $defaultBranch"

    if ($New -and -not $Update) {
        Write-Error "-New can only be used together with -Update"
        return
    }

    if ($Merge) {
        if ($hasUncommittedChanges) {
            $status = git status --porcelain
            Write-Error "Cannot merge with uncommitted changes:" + $status
            return
        }

        $openPr = gh pr list --head $currentBranch --state open --json number,title,url,baseRefName --jq '.[0]'
        Debug-Log "Open PR check result: $openPr"
        
        if (-not $openPr -or $openPr -eq '' -or $openPr -eq 'null') {
            Write-Error "No open PR found for branch '$currentBranch'"
            return
        }

        $prData = $openPr | ConvertFrom-Json
        $prNumber = $prData.number
        $prBase = $prData.baseRefName
        Write-Host "Found open PR #$prNumber targeting '$prBase'" -ForegroundColor Cyan
        Write-Host "PR URL: $($prData.url)" -ForegroundColor Cyan

        Write-Host ""
        Write-Host "Press ENTER to merge, or ESCAPE to cancel..." -ForegroundColor Magenta
        $key = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)

        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            Write-Host "Cancelled. PR not merged." -ForegroundColor Red
            return
        }

        Write-Host ""
        Write-Host "Merging PR #$prNumber..." -ForegroundColor Green
        Debug-Log "Running merge command for PR #$prNumber"
        gh pr merge $prNumber --squash --delete-branch

        Write-Host "Switching to $prBase and pulling latest..." -ForegroundColor Green
        Debug-Log "Checking out '$prBase' and pulling latest from origin"
        git checkout $prBase
        git pull origin $prBase

        Write-Host ""
        Write-Host "Merge complete!" -ForegroundColor Green
        return
    }

    if ($Update) {
        if ($Merge) {
            Write-Error "-Merge and -Update cannot be used together"
            return
        }

        if (-not $hasUncommittedChanges) {
            Write-Error "No uncommitted changes found. Nothing to update."
            return
        }

        if ($currentBranch -eq $defaultBranch) {
            Write-Error "-Update cannot be used on the default branch '$defaultBranch'."
            return
        }

        $openPr = gh pr list --head $currentBranch --state open --json number,title,body,url --jq '.[0]'
        Debug-Log "Open PR check result: $openPr"
        if (-not $openPr -or $openPr -eq '' -or $openPr -eq 'null') {
            Write-Error "No open PR found for branch '$currentBranch'. Create a PR first or run without -Update."
            return
        }

        $prData = $openPr | ConvertFrom-Json
        $prNumber = $prData.number
        $currentPrTitle = [string]$prData.title
        $currentPrDescription = [string]$prData.body
        Debug-Log "Current PR title length: $($currentPrTitle.Length)"
        Debug-Log "Current PR description length: $($currentPrDescription.Length)"

        Write-Host "Uncommitted changes detected:" -ForegroundColor Yellow
        git status --short
        Write-Host ""

        $branchDiff = git diff "$defaultBranch...HEAD"
        $stagedDiff = git diff --staged
        $unstagedDiff = git diff
        $untrackedSections = Get-UntrackedFilePromptSections

        Debug-Log "Branch diff vs '$defaultBranch' length: $($branchDiff.Length) characters"
        Debug-Log "Staged diff length: $($stagedDiff.Length) characters"
        Debug-Log "Unstaged diff length: $($unstagedDiff.Length) characters"
        Debug-Log "Untracked file sections: $($untrackedSections.Count)"

        $diffParts = @()
        if ($branchDiff) {
            $diffParts += "=== Existing branch changes vs $defaultBranch ===`n$branchDiff"
        }
        if ($stagedDiff) {
            $diffParts += "=== Newly staged changes ===`n$stagedDiff"
        }
        if ($unstagedDiff) {
            $diffParts += "=== Newly unstaged changes ===`n$unstagedDiff"
        }
        if ($untrackedSections.Count -gt 0) {
            $diffParts += $untrackedSections
        }

        $combinedDiff = $diffParts -join "`n`n"
        Debug-Log "Combined update diff length: $($combinedDiff.Length) characters"

        if (-not $combinedDiff) {
            Write-Error "No diff content found to generate update details."
            return
        }

        if ($New) {
            Write-Host "Generating updated commit message and PR details with AI..." -ForegroundColor Cyan
        } else {
            Write-Host "Generating updated commit message with AI..." -ForegroundColor Cyan
        }
        $aiResult = Invoke-AIRequest -Diff $combinedDiff -NeedsCommitMessage $true -NeedsPrDetails $New -CurrentPrTitle $currentPrTitle -CurrentPrDescription $currentPrDescription

        $commitMessage = $aiResult.'commit-message'
        $title = if ($New) { $aiResult.title } else { $currentPrTitle }
        $description = if ($New) { $aiResult.description } else { $currentPrDescription }

        if (-not $commitMessage -or ($New -and -not $title)) {
            Write-Error "AI returned incomplete response"
            return
        }

        Write-Host ""
        Write-Host "=== Update Preview ===" -ForegroundColor Cyan
        Write-Host "PR: #$prNumber ($($prData.url))" -ForegroundColor White
        Write-Host "Branch: $currentBranch" -ForegroundColor White
        Write-Host "Commit: $commitMessage" -ForegroundColor White
        Write-Host "" 
        if ($New) {
            Write-Host "PR Title: $title" -ForegroundColor Yellow
            Write-Host "PR Description: $description" -ForegroundColor White
        } else {
            Write-Host "PR Title: (unchanged) $title" -ForegroundColor Yellow
            Write-Host "PR Description: (unchanged) $description" -ForegroundColor White
        }
        Write-Host ""

        if ($New) {
            Write-Host "Press ENTER to commit, push, and update PR; ESCAPE to cancel..." -ForegroundColor Magenta
        } else {
            Write-Host "Press ENTER to commit and push; ESCAPE to cancel..." -ForegroundColor Magenta
        }
        $key = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)

        if ($key.VirtualKeyCode -eq 27) {
            Write-Host ""
            Write-Host "Cancelled. No commit, push, or PR update performed." -ForegroundColor Red
            return
        }

        Write-Host ""
        Write-Host "Committing changes..." -ForegroundColor Green
        Debug-Log "Staging all changes for update"
        git add .
        Debug-Log "Creating commit with message: $commitMessage"
        git commit -m $commitMessage

        Write-Host "Pushing changes to remote branch..." -ForegroundColor Green
        Debug-Log "Pushing '$currentBranch' to origin"
        git push origin $currentBranch

        if ($New) {
            Write-Host "Updating PR #$prNumber..." -ForegroundColor Green
            Debug-Log "Editing PR #$prNumber title/body"
            gh pr edit $prNumber --title $title --body $description
        } else {
            Debug-Log "Skipping PR title/description update (use -New with -Update to enable)"
        }

        Write-Host ""
        if ($New) {
            Write-Host "PR updated successfully!" -ForegroundColor Green
        } else {
            Write-Host "PR commit pushed successfully!" -ForegroundColor Green
        }
        Write-Host "New Commit Message: $commitMessage" -ForegroundColor White
        if ($New) {
            Write-Host "Updated PR Title: $title" -ForegroundColor Yellow
            Write-Host "Updated PR Description: $description" -ForegroundColor White
        } else {
            Write-Host "PR Title: (unchanged) $title" -ForegroundColor Yellow
            Write-Host "PR Description: (unchanged) $description" -ForegroundColor White
        }
        Write-Host "PR URL: $($prData.url)" -ForegroundColor Cyan
        return
    }

    if ($hasUncommittedChanges) {
        Write-Host "Uncommitted changes detected:" -ForegroundColor Yellow
        git status --short
        Write-Host ""

        $diff = git diff --staged
        $unstagedDiff = git diff
        $untrackedSections = Get-UntrackedFilePromptSections
        Debug-Log "Staged diff length: $($diff.Length) characters"
        Debug-Log "Unstaged diff length: $($unstagedDiff.Length) characters"
        Debug-Log "Untracked file sections: $($untrackedSections.Count)"

        $diffParts = @()
        if ($diff) {
            $diffParts += "=== Newly staged changes ===`n$diff"
        }
        if ($unstagedDiff) {
            $diffParts += "=== Newly unstaged changes ===`n$unstagedDiff"
        }
        if ($untrackedSections.Count -gt 0) {
            $diffParts += $untrackedSections
        }

        $combinedDiff = $diffParts -join "`n`n"
        Debug-Log "Combined diff length: $($combinedDiff.Length) characters"

        Write-Host "Generating commit message and PR details with AI..." -ForegroundColor Cyan
        $aiResult = Invoke-AIRequest -Diff $combinedDiff -NeedsCommitMessage $true

        $commitMessage = $aiResult.'commit-message'
        $title = $aiResult.title
        $description = $aiResult.description

        if (-not $commitMessage -or -not $title) {
            Write-Error "AI returned incomplete response"
            return
        }

        Debug-Log "Commit message: $commitMessage"
        Debug-Log "PR title: $title"
        Debug-Log "PR description: $description"

        $branchName = Get-GeneratedBranchName -Title $title
        Debug-Log "Branch name: $branchName"
    } else {
        Write-Host "No uncommitted changes." -ForegroundColor Yellow
        Write-Host "Current branch: $currentBranch" -ForegroundColor Cyan

        if ($currentBranch -eq $defaultBranch) {
            Write-Error "On default branch ($defaultBranch) with no changes. Nothing to do."
            return
        }

        $openPr = gh pr list --head $currentBranch --state open --json number,title,url --jq '.[0]'
        Debug-Log "Open PR check result: $openPr"
        if ($openPr -and $openPr -ne '' -and $openPr -ne 'null') {
            $prData = $openPr | ConvertFrom-Json
            Write-Host "An open PR already exists for this branch: #$($prData.number)" -ForegroundColor Yellow
            Write-Host "PR URL: $($prData.url)" -ForegroundColor Cyan
            return
        }

        $commitRange = "$defaultBranch..$currentBranch"
        Debug-Log "Getting diff for range: $commitRange"
        $combinedDiff = git log $commitRange --oneline -1 --format="" -p
        if (-not $combinedDiff) {
            Debug-Log "No diff from log, trying git diff"
            $combinedDiff = git diff $defaultBranch..$currentBranch
        }
        Debug-Log "Combined diff length: $($combinedDiff.Length) characters"
        if (-not $combinedDiff) {
            Write-Error "No changes found between $defaultBranch and $currentBranch."
            return
        }

        Write-Host "Generating PR details with AI..." -ForegroundColor Cyan
        $aiResult = Invoke-AIRequest -Diff $combinedDiff -NeedsCommitMessage $false

        $title = $aiResult.title
        $description = $aiResult.description

        if (-not $title) {
            Write-Error "AI returned incomplete response"
            return
        }

        $commitMessage = git log -1 --format="%s"
        $branchName = $currentBranch
        Debug-Log "PR title: $title"
        Debug-Log "PR description: $description"
    }

    Write-Host ""
    Write-Host "=== PR Details ===" -ForegroundColor Cyan
    Write-Host "Branch: $branchName" -ForegroundColor White
    Write-Host "Commit: $commitMessage" -ForegroundColor White
    Write-Host ""
    Write-Host "PR Title: $title" -ForegroundColor Yellow
    Write-Host "PR Description: $description" -ForegroundColor White
    Write-Host ""

    Write-Host "Press ENTER to create the PR, or ESCAPE to cancel..." -ForegroundColor Magenta

    $key = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)

    if ($key.VirtualKeyCode -eq 27) {
        Write-Host ""
        Write-Host "Cancelled. PR not created." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Creating PR..." -ForegroundColor Green
    Debug-Log "Creating PR with title: '$title' on base: $defaultBranch"

    if ($hasUncommittedChanges) {
        Write-Host "Creating branch: $branchName" -ForegroundColor Green
        Debug-Log "Creating and switching to branch '$branchName'"
        git checkout -b $branchName

        Write-Host "Committing changes..." -ForegroundColor Green
        Debug-Log "Staging all changes for initial PR commit"
        git add .
        Debug-Log "Creating commit with message: $commitMessage"
        git commit -m $commitMessage
    }

    Write-Host "Pushing branch to remote..." -ForegroundColor Green
    Debug-Log "Pushing '$branchName' with upstream to origin"
    git push -u origin $branchName

    Debug-Log "Creating PR on base '$defaultBranch'"
    $prUrl = gh pr create `
        --title $title `
        --body $description `
        --base $defaultBranch

    Write-Host ""
    Write-Host "PR created successfully!" -ForegroundColor Green
    Write-Host "PR URL: $prUrl" -ForegroundColor Cyan
}

Export-ModuleMember -Function yeet
