$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$workflow = Get-Content -Raw (Join-Path $repositoryRoot '.github/workflows/validate-zscaler-via-cribl-asim.yml')

# Branch protection requires `validate` for every PR, including action-only PRs.
# A path-filtered workflow would leave that required check pending.
if ($workflow -cnotmatch '(?m)^  pull_request:[ \t]*\r?\n(?=  (?:push|schedule|workflow_dispatch):)') {
    throw 'The required validate workflow must run on every pull request without filters.'
}

Write-Host 'Required check trigger validation passed.'
