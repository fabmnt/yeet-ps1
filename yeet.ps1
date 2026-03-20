param(
    [switch]$DebugMode,
    [Alias("m")]
    [switch]$Merge,
    [Alias("u")]
    [switch]$Update,
    [Alias("h")]
    [switch]$Help
)

$ErrorActionPreference = "Stop"

function Show-Help {
    Write-Host ""
    Write-Host "yeet - Git PR Creator CLI" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: yeet [-DebugMode] [-Merge] [-Update] [-Help]" -ForegroundColor White
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -DebugMode, -D          Enable debug output" -ForegroundColor White
    Write-Host "  -Merge, -m              Merge an existing PR to base branch" -ForegroundColor White
    Write-Host "  -Update, -u             Update existing PR from current branch changes" -ForegroundColor White
    Write-Host "  -Help, -h               Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "Description:" -ForegroundColor Yellow
    Write-Host "  Creates PRs with AI-generated commit messages, titles, and descriptions." -ForegroundColor White
    Write-Host "  With -Merge: merges the current branch PR and updates local base branch." -ForegroundColor White
    Write-Host "  With -Update: commits uncommitted changes and updates open PR title/body." -ForegroundColor White
    Write-Host ""
    exit 0
}

if ($Help) {
    Show-Help
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
    exit 1
}
Debug-Log "OPENROUTER_API_KEY detected"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI ('gh') is not installed or not available on PATH. Install it from https://cli.github.com/ and try again."
    exit 1
}
Debug-Log "GitHub CLI detected"

Debug-Log "Checking GitHub CLI authentication status"
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "GitHub CLI is not authenticated. Please run 'gh auth login' first."
    exit 1
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

function Invoke-AIRequest {
    param(
        [string]$Diff,
        [bool]$NeedsCommitMessage,
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
    $titlePrompt = if ($hasCurrentPrContext) {
        "Update the existing pull request title using the provided diff and current PR details. Make granular edits and preserve the current intent unless the new changes require adjustment. Keep the title brief (prefer 40-60 characters, hard max 72) while still covering the overall PR scope, including existing branch changes and newly added changes. Return only the title text, no markdown, no quotes."
    } else {
        "Generate a pull request title from the diff. Keep the title brief (prefer 40-60 characters, hard max 72) while still covering the full PR scope. Return only the title text, no markdown, no quotes."
    }
    $descriptionPrompt = if ($hasCurrentPrContext) {
        "Update the existing pull request description in markdown using the provided diff and current PR details. Make granular edits to the current content instead of fully rewriting it. Preserve sections and wording where still accurate, and only adjust what changed. Return only the description body."
    } else {
        "Generate a pull request description in markdown from the diff. Use sections: ## Summary, ## Changes (bullet list), ## Notes. Return only the description body."
    }
    $commitPrompt = "Generate a git commit message from the diff. Keep it brief and to the point (prefer 30-55 characters, hard max 72). Return only one line in conventional commits format, no markdown, no quotes."

    Debug-Log "Using model: $model"

    $requestInput = "Diff:`n$Diff"
    if ($hasCurrentPrContext) {
        $requestInput += "`n`nCurrent PR title:`n$CurrentPrTitle`n`nCurrent PR description:`n$CurrentPrDescription"
        Debug-Log "Including current PR title/description in AI context for granular updates"
    }

    $jobScript = {
        param($ApiKey, $Model, $Prompt, $InputText, $MaxTokens, $RequestName)

        $lastErrorMessage = ""
        for ($attempt = 1; $attempt -le 3; $attempt++) {
            try {
                $response = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/chat/completions" `
                    -Method POST `
                    -Headers @{
                        "Authorization" = "Bearer $ApiKey"
                        "Content-Type" = "application/json"
                    } `
                    -Body (@{
                        model = $Model
                        messages = @(
                            @{ role = "system"; content = $Prompt }
                            @{ role = "user"; content = $InputText }
                        )
                        max_tokens = $MaxTokens
                        reasoning = @{ enabled = $false }
                    } | ConvertTo-Json -Depth 10 -Compress)

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

                if ($output) {
                    return [PSCustomObject]@{
                        ok = $true
                        request = $RequestName
                        output = $output
                        attempts = $attempt
                        error = ""
                    }
                }
                $lastErrorMessage = "Empty AI response"
            } catch {
                $lastErrorMessage = $_.Exception.Message
            }
        }

        return [PSCustomObject]@{
            ok = $false
            request = $RequestName
            output = ""
            attempts = 3
            error = $lastErrorMessage
        }
    }

    $jobs = @()
    if ($NeedsCommitMessage) {
        $jobs += Start-Job -ScriptBlock $jobScript -ArgumentList $apiKey, $model, $commitPrompt, $requestInput, 120, "commit message"
    }
    $jobs += Start-Job -ScriptBlock $jobScript -ArgumentList $apiKey, $model, $titlePrompt, $requestInput, 120, "PR title"
    $jobs += Start-Job -ScriptBlock $jobScript -ArgumentList $apiKey, $model, $descriptionPrompt, $requestInput, 1200, "PR description"
    Debug-Log "Started $($jobs.Count) AI request job(s)"

    Wait-Job -Job $jobs | Out-Null
    Debug-Log "All AI request jobs completed"
    $results = @()
    foreach ($job in $jobs) {
        $jobOutput = Receive-Job -Job $job -ErrorAction SilentlyContinue
        if ($jobOutput -is [System.Array]) {
            $jobOutput = $jobOutput[-1]
        }

        $results += [PSCustomObject]@{
            id = $job.Id
            state = $job.State
            output = $jobOutput
        }
    }
    $jobs | Remove-Job -Force

    $failedRequests = @($results | Where-Object { $_.state -ne "Completed" -or -not $_.output -or -not $_.output.ok })
    if ($failedRequests.Count -gt 0) {
        $failedDetails = ($failedRequests | ForEach-Object {
            $name = if ($_.output -and $_.output.request) { $_.output.request } else { "unknown request" }
            $errorMessage = if ($_.output -and $_.output.error) { $_.output.error } else { "No error response captured" }
            "$name ($errorMessage)"
        }) -join "; "

        Write-Error "AI request failed after 3 retries: $failedDetails"
        exit 1
    }

    $resultIndex = 0
    $commitMessage = $null
    if ($NeedsCommitMessage) {
        $commitMessage = [string]$results[$resultIndex].output.output
        if ($commitMessage.Length -gt 72) {
            $commitMessage = $commitMessage.Substring(0, 72).Trim()
        }
        $resultIndex++
    }

    $title = [string]$results[$resultIndex].output.output
    $resultIndex++
    $description = [string]$results[$resultIndex].output.output

    Debug-Log "Generated commit message length: $($commitMessage.Length)"
    Debug-Log "Generated title length: $($title.Length)"
    Debug-Log "Generated description length: $($description.Length)"

    return [PSCustomObject]@{
        'commit-message' = $commitMessage
        title = $title
        description = $description
    }
}

Debug-Log "Starting Git PR Creator"

$status = git status --porcelain
$hasUncommittedChanges = $status -ne $null -and $status.Length -gt 0
Debug-Log "Has uncommitted changes: $hasUncommittedChanges"

$currentBranch = git branch --show-current
if (-not $currentBranch) {
    Write-Error "Not on a branch. Please checkout a branch first."
    exit 1
}
Debug-Log "Current branch: $currentBranch"

$defaultBranch = gh repo view --json defaultBranchRef --jq .defaultBranchRef.name
if (-not $defaultBranch) {
    $defaultBranch = "main"
}
Debug-Log "Default branch: $defaultBranch"

if ($Merge) {
    if ($hasUncommittedChanges) {
        $status = git status --porcelain
        Write-Error "Cannot merge with uncommitted changes:" + $status
        exit 1
    }

    $openPr = gh pr list --head $currentBranch --state open --json number,title,url,baseRefName --jq '.[0]'
    Debug-Log "Open PR check result: $openPr"
    
    if (-not $openPr -or $openPr -eq '' -or $openPr -eq 'null') {
        Write-Error "No open PR found for branch '$currentBranch'"
        exit 1
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
        exit 0
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
    exit 0
}

if ($Update) {
    if ($Merge) {
        Write-Error "-Merge and -Update cannot be used together"
        exit 1
    }

    if (-not $hasUncommittedChanges) {
        Write-Error "No uncommitted changes found. Nothing to update."
        exit 1
    }

    if ($currentBranch -eq $defaultBranch) {
        Write-Error "-Update cannot be used on the default branch '$defaultBranch'."
        exit 1
    }

    $openPr = gh pr list --head $currentBranch --state open --json number,title,body,url --jq '.[0]'
    Debug-Log "Open PR check result: $openPr"
    if (-not $openPr -or $openPr -eq '' -or $openPr -eq 'null') {
        Write-Error "No open PR found for branch '$currentBranch'. Create a PR first or run without -Update."
        exit 1
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

    Debug-Log "Branch diff vs '$defaultBranch' length: $($branchDiff.Length) characters"
    Debug-Log "Staged diff length: $($stagedDiff.Length) characters"
    Debug-Log "Unstaged diff length: $($unstagedDiff.Length) characters"

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

    $combinedDiff = $diffParts -join "`n`n"
    Debug-Log "Combined update diff length: $($combinedDiff.Length) characters"

    if (-not $combinedDiff) {
        Write-Error "No diff content found to generate update details."
        exit 1
    }

    Write-Host "Generating updated commit message and PR details with AI..." -ForegroundColor Cyan
    $aiResult = Invoke-AIRequest -Diff $combinedDiff -NeedsCommitMessage $true -CurrentPrTitle $currentPrTitle -CurrentPrDescription $currentPrDescription

    $commitMessage = $aiResult.'commit-message'
    $title = $aiResult.title
    $description = $aiResult.description

    if (-not $commitMessage -or -not $title) {
        Write-Error "AI returned incomplete response"
        exit 1
    }

    Write-Host ""
    Write-Host "=== Update Preview ===" -ForegroundColor Cyan
    Write-Host "PR: #$prNumber ($($prData.url))" -ForegroundColor White
    Write-Host "Branch: $currentBranch" -ForegroundColor White
    Write-Host "Commit: $commitMessage" -ForegroundColor White
    Write-Host "" 
    Write-Host "PR Title: $title" -ForegroundColor Yellow
    Write-Host "PR Description: $description" -ForegroundColor White
    Write-Host ""

    Write-Host "Press ENTER to commit, push, and update PR; ESCAPE to cancel..." -ForegroundColor Magenta
    $key = $Host.UI.RawUI.ReadKey([System.Management.Automation.Host.ReadKeyOptions]::NoEcho -bor [System.Management.Automation.Host.ReadKeyOptions]::IncludeKeyDown)

    if ($key.VirtualKeyCode -eq 27) {
        Write-Host ""
        Write-Host "Cancelled. No commit, push, or PR update performed." -ForegroundColor Red
        exit 0
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

    Write-Host "Updating PR #$prNumber..." -ForegroundColor Green
    Debug-Log "Editing PR #$prNumber title/body"
    gh pr edit $prNumber --title $title --body $description

    Write-Host ""
    Write-Host "PR updated successfully!" -ForegroundColor Green
    Write-Host "New Commit Message: $commitMessage" -ForegroundColor White
    Write-Host "Updated PR Title: $title" -ForegroundColor Yellow
    Write-Host "Updated PR Description: $description" -ForegroundColor White
    Write-Host "PR URL: $($prData.url)" -ForegroundColor Cyan
    exit 0
}

if ($hasUncommittedChanges) {
    Write-Host "Uncommitted changes detected:" -ForegroundColor Yellow
    git status --short
    Write-Host ""

    $diff = git diff --staged
    $unstagedDiff = git diff
    Debug-Log "Staged diff length: $($diff.Length) characters"
    Debug-Log "Unstaged diff length: $($unstagedDiff.Length) characters"
    $combinedDiff = if ($diff) { $diff + "`n" + $unstagedDiff } else { $unstagedDiff }
    Debug-Log "Combined diff length: $($combinedDiff.Length) characters"

    Write-Host "Generating commit message and PR details with AI..." -ForegroundColor Cyan
    $aiResult = Invoke-AIRequest -Diff $combinedDiff -NeedsCommitMessage $true

    $commitMessage = $aiResult.'commit-message'
    $title = $aiResult.title
    $description = $aiResult.description

    if (-not $commitMessage -or -not $title) {
        Write-Error "AI returned incomplete response"
        exit 1
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
        exit 1
    }

    $openPr = gh pr list --head $currentBranch --state open --json number,title,url --jq '.[0]'
    Debug-Log "Open PR check result: $openPr"
    if ($openPr -and $openPr -ne '' -and $openPr -ne 'null') {
        $prData = $openPr | ConvertFrom-Json
        Write-Host "An open PR already exists for this branch: #$($prData.number)" -ForegroundColor Yellow
        Write-Host "PR URL: $($prData.url)" -ForegroundColor Cyan
        exit 0
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
        exit 1
    }

    Write-Host "Generating PR details with AI..." -ForegroundColor Cyan
    $aiResult = Invoke-AIRequest -Diff $combinedDiff -NeedsCommitMessage $false

    $title = $aiResult.title
    $description = $aiResult.description

    if (-not $title) {
        Write-Error "AI returned incomplete response"
        exit 1
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
    exit 0
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
