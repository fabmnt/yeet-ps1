# yeet

> Stop wasting tokens from your main coding agents (Codex, Claude Code) just for creating commit messages, PR titles, and descriptions. **yeet** allows you to use free OpenRouter models to achieve this seamlessly.

`yeet` is a Windows-first CLI helper for working with GitHub pull requests.

It uses:
- `git` for branch/commit/push operations
- `gh` (GitHub CLI) for PR lookup/create/edit/merge
- OpenRouter (`OPENROUTER_API_KEY`) to generate commit messages and PR titles/descriptions from diffs

The command entrypoint is `yeet.cmd`, which invokes `yeet.ps1`.

## Requirements

- PowerShell
- `git` installed and available on `PATH`
- `gh` installed and authenticated (`gh auth login`)
- `OPENROUTER_API_KEY` environment variable set (see [Setup](#setup) below)

Optional:
- `OPENROUTER_MODEL_ID` (or `OPENROUTER_MODEL`) to override the default model

## Setup

### OpenRouter API Key

1. Get your free API key from [OpenRouter](https://openrouter.ai/keys)
2. Set the `OPENROUTER_API_KEY` environment variable:

   **PowerShell (current session):**
   ```powershell
   $env:OPENROUTER_API_KEY = "sk-or-v1-..."
   ```

   **PowerShell (permanent):**
   ```powershell
   [Environment]::SetEnvironmentVariable("OPENROUTER_API_KEY", "sk-or-v1-...", "User")
   ```

   **Windows Command Prompt:**
   ```cmd
   setx OPENROUTER_API_KEY "sk-or-v1-..."
   ```

### OpenRouter Model (Optional)

By default, yeet uses the free model: `nvidia/nemotron-3-super-120b-a12b:free`

To use a different model, set one of these environment variables:

```powershell
# Option 1: OPENROUTER_MODEL_ID (recommended)
$env:OPENROUTER_MODEL_ID = "anthropic/claude-3.5-sonnet"

# Option 2: OPENROUTER_MODEL (alternative)
$env:OPENROUTER_MODEL = "google/gemini-pro"
```

Find available models at [openrouter.ai/models](https://openrouter.ai/models).

## Installation

Install from [PowerShell Gallery](https://www.powershellgallery.com/packages/yeet):

```powershell
Install-Module -Name yeet -Scope CurrentUser
Import-Module yeet
```

Add `Import-Module yeet` to your PowerShell profile to auto-load.

## Initial Setup

After installation, you need to configure your OpenRouter API key. You can do this in two ways:

### Option 1: Interactive Setup (Recommended)

Run the setup command and enter your API key when prompted:

```powershell
yeet -Setup
```

Or use the short form:

```powershell
yeet -s
```

The setup will:
- Prompt you for your OpenRouter API key (input is hidden for security)
- Save the key to your PowerShell profile for persistence across sessions
- Set the key for the current session immediately

### Option 2: Manual Configuration

If you prefer to set the environment variable manually:

**PowerShell (current session):**
```powershell
$env:OPENROUTER_API_KEY = "sk-or-v1-..."
```

**PowerShell (permanent):**
```powershell
[Environment]::SetEnvironmentVariable("OPENROUTER_API_KEY", "sk-or-v1-...", "User")
```

**Windows Command Prompt:**
```cmd
setx OPENROUTER_API_KEY "sk-or-v1-..."
```

**Note:** If you run `yeet` without an API key configured (except for `-v` or `-h`), it will automatically enter setup mode and prompt you for the key.

## Usage

```powershell
yeet [-DebugMode] [-Merge] [-Update [-New]] [-Push] [-Setup] [-Version] [-Help]
```

## CLI Arguments

- `-Help`, `-h`
  - Shows help and exits.

- `-Setup`, `-s`
  - Enters interactive setup mode to configure OpenRouter API key.

- `-DebugMode`, `-D`
  - Enables debug logging output.

- `-Merge`, `-m`
  - Merges the open PR for the current branch (squash + delete branch).
  - Then checks out the PR base branch and pulls latest changes.
  - Fails if uncommitted changes exist.

- `-Update`, `-u`
  - For an existing open PR on the current branch.
  - Uses AI to generate a commit message from current changes.
  - Stages all changes, commits, and pushes to the PR branch.

- `-New`, `-n`
  - Only valid with `-Update`.
  - Also regenerates and updates PR title/body (not just commit + push).

- `-Push`
  - Generates a commit message from current changes and pushes directly without creating a PR.
  - Shows the generated commit message and waits for confirmation.
  - Cannot be combined with `-Merge` or `-Update`.

- `-Version`, `-v`
  - Shows the current version of yeet.

## Behavior (by mode)

### Default mode (`yeet` with no flags)

- If you have uncommitted changes:
  - Generates commit message + PR title/body from diff.
  - Shows a preview and waits for confirmation.
  - Creates a branch from generated title, commits, pushes, and opens a PR.

- If you have no uncommitted changes:
  - If on default branch: exits with error.
  - If on feature branch and PR exists: prints PR info and exits.
  - If on feature branch without open PR: generates PR title/body from branch diff, then creates PR.

### Update mode (`yeet -u`)

- Requires:
  - uncommitted changes
  - current branch is not default branch
  - existing open PR for current branch
- Commits and pushes changes to the PR branch.
- With `-n`, also updates PR title/body.

### Merge mode (`yeet -m`)

- Requires open PR for current branch and a clean working tree.
- Performs `gh pr merge --squash --delete-branch`.
- Checks out the PR base branch and pulls latest from origin.

### Push mode (`yeet -p`)

- Requires uncommitted changes.
- Uses AI to generate a commit message from current changes.
- Shows a preview and waits for confirmation.
- Commits all changes and pushes directly to the current branch without creating a PR.
- Cannot be combined with `-Merge` or `-Update`.

## Examples

```powershell
# Initial setup (configure OpenRouter API key)
yeet -s

# Create a PR from local changes
yeet

# Update current PR with new commits
yeet -u

# Update current PR and refresh title/body
yeet -u -n

# Merge current branch PR
yeet -m

# Generate commit message and push directly (no PR)
yeet -Push

# Show version
yeet -v

# Show help
yeet -h
```

## Notes

- This tool is interactive and asks for ENTER/ESC confirmation before create/update/merge actions.
- It exits with non-zero status on validation or API/auth failures.
