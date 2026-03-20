param(
    [string]$BranchPrefix = "feat",
    [switch]$DebugMode,
    [Alias("m")]
    [switch]$Merge
)

$ErrorActionPreference = "Stop"

function Debug-Log {
    param([string]$Message)
    if ($DebugMode) {
        Write-Host "[DEBUG] $Message" -ForegroundColor DarkGray
    }
}

$profilePath = "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
if (-not $env:OPENROUTER_API_KEY -and (Test-Path $profilePath)) {
    . $profilePath
}

$apiKey = $env:OPENROUTER_API_KEY
if (-not $apiKey) {
    Write-Error "OPENROUTER_API_KEY environment variable is not set"
    exit 1
}

function Get-CleanContent {
    param([string]$Content)
    $Content = $Content -replace '(?s)<(?:think|analysis|reasoning)>.*?</(?:think|analysis|reasoning)>', ''
    $Content = $Content -replace '(?s)<scratchpad>.*?</scratchpad>', ''
    $Content = $Content -replace '(?i)^(?:here(?:''s| is) (?:the |your )?(?:commit message|message|title|description):?\s*)', ''
    $Content = $Content -replace '^```json\s*|```$', ''
    $Content.Trim()
}

function Invoke-AIRequest {
    param([string]$Diff, [bool]$NeedsCommitMessage)

    $prompt = if ($NeedsCommitMessage) {
        "Return ONLY a JSON object with no markdown formatting. Properties:
- commit-message: A concise conventional commit message (max 72 chars)
- title: A short PR title (max 72 chars)  
- description: A professional PR description with this structure:
  1. A brief summary of what was changed and why
  2. A bullet list of key changes
  3. Any important implementation details or considerations

Example: {""commit-message"": ""fix: resolve image navigation bug"", ""title"": ""Fix image navigation in ExecutionFlowCard"", ""description"": ""## Summary\nFixed the image navigation behavior to properly track and display execution images.\n\n## Changes\n- Added auto-follow state for latest image tracking\n- Fixed navigation handlers for previous/next buttons\n- Removed unnecessary image array reversal\n\n## Notes\nThe auto-follow feature ensures users stay on the latest image during execution while allowing manual navigation away from it.""}"
    } else {
        "Return ONLY a JSON object with no markdown formatting. Properties:
- title: A short PR title (max 72 chars)
- description: A professional PR description with this structure:
  1. A brief summary of what was changed and why
  2. A bullet list of key changes
  3. Any important implementation details or considerations

Example: {""title"": ""Fix image navigation in ExecutionFlowCard"", ""description"": ""## Summary\nFixed the image navigation behavior to properly track and display execution images.\n\n## Changes\n- Added auto-follow state for latest image tracking\n- Fixed navigation handlers for previous/next buttons\n- Removed unnecessary image array reversal\n\n## Notes\nThe auto-follow feature ensures users stay on the latest image during execution while allowing manual navigation away from it.""}"
    }

    $response = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/chat/completions" `
        -Method POST `
        -Headers @{
            "Authorization" = "Bearer $apiKey"
            "Content-Type" = "application/json"
        } `
        -Body (@{
            model = "openrouter/free"
            messages = @(
                @{ role = "system"; content = $prompt }
                @{ role = "user"; content = "Diff:`n$Diff" }
            )
            max_tokens = 2000
        } | ConvertTo-Json -Depth 10 -Compress)

    $message = $response.choices[0].message
    $rawContent = if ($message.content) { $message.content } elseif ($message.reasoning) { $message.reasoning } else { "" }
    $cleanContent = Get-CleanContent $rawContent
    
    if ($cleanContent -match '\{[\s\S]*\}') {
        $cleanContent = $Matches[0]
    }
    
    Debug-Log "Cleaned content: $cleanContent"

    try {
        $json = $cleanContent | ConvertFrom-Json
        return $json
    } catch {
        Write-Error "Failed to parse AI response as JSON: $cleanContent"
        exit 1
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
    gh pr merge $prNumber --squash --delete-branch

    Write-Host "Switching to $prBase and pulling latest..." -ForegroundColor Green
    git checkout $prBase
    git pull origin $prBase

    Write-Host ""
    Write-Host "Merge complete!" -ForegroundColor Green
    exit 0
}

if ($hasUncommittedChanges) {
    Write-Host "Uncommitted changes detected:" -ForegroundColor Yellow
    git status --short
    Write-Host ""

    $diff = git diff --staged
    $unstagedDiff = git diff
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

    $branchName = $title -replace '\s+', '-' -replace '[^a-zA-Z0-9\-]', ''
    $branchName = "$BranchPrefix/$branchName".ToLower()
    Debug-Log "Branch name: $branchName"

    Write-Host "Creating branch: $branchName" -ForegroundColor Green
    git checkout -b $branchName

    Write-Host "Committing changes..." -ForegroundColor Green
    git add .
    git commit -m $commitMessage
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

Write-Host "Pushing branch to remote..." -ForegroundColor Green
git push -u origin $branchName

$prUrl = gh pr create `
    --title $title `
    --body $description `
    --base $defaultBranch

Write-Host ""
Write-Host "PR created successfully!" -ForegroundColor Green
Write-Host "PR URL: $prUrl" -ForegroundColor Cyan