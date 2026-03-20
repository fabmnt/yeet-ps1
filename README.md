# yeet

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
- `OPENROUTER_API_KEY` environment variable set

Optional:
- `OPENROUTER_MODEL_ID` (or `OPENROUTER_MODEL`) to override the default model

## Installation

Install from [PowerShell Gallery](https://www.powershellgallery.com/packages/yeet):

```powershell
Install-Module -Name yeet -Scope CurrentUser
Import-Module yeet
```

Add `Import-Module yeet` to your PowerShell profile to auto-load.

## Usage

```powershell
yeet [-DebugMode] [-Merge] [-Update [-New]] [-Help]
```

## CLI Arguments

- `-Help`, `-h`
  - Shows help and exits.

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

## Examples

```powershell
# Create a PR from local changes
yeet

# Update current PR with new commits
yeet -u

# Update current PR and refresh title/body
yeet -u -n

# Merge current branch PR
yeet -m

# Show help
yeet -h
```

## Notes

- This tool is interactive and asks for ENTER/ESC confirmation before create/update/merge actions.
- It exits with non-zero status on validation or API/auth failures.
