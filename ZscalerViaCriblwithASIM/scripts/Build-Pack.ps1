[CmdletBinding()]
param(
    [string]$Version = '2.0.0'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$package = Join-Path $root 'Package'
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist "ZscalerViaCriblwithASIM-$Version"
$archive = Join-Path $dist "ZscalerViaCriblwithASIM-$Version.zip"

New-Item -ItemType Directory -Force -Path $package, $dist | Out-Null

& (Join-Path $PSScriptRoot 'Generate-DeploymentManifests.ps1')

& az bicep build `
    --file (Join-Path $root 'infra\main.bicep') `
    --outfile (Join-Path $package 'mainTemplate.json')
if ($LASTEXITCODE -ne 0) {
    throw 'Bicep compilation failed.'
}

Get-ChildItem -Path $root -Recurse -File -Filter '*.json' |
    Where-Object FullName -NotMatch '\\dist\\' |
    ForEach-Object {
        Get-Content $_.FullName -Raw | ConvertFrom-Json | Out-Null
    }

if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$items = @(
    '.github',
    '.gitignore',
    'Analytic Rules',
    'Content',
    'Cribl',
    'docs',
    'Hunting Queries',
    'infra',
    'Package',
    'Parsers',
    'Playbooks',
    'RepositoryContent',
    'scripts',
    'Workbooks',
    'LICENSE',
    'README.md',
    'SolutionMetadata.json',
    'THIRD_PARTY_NOTICES.md'
)

foreach ($item in $items) {
    Copy-Item -LiteralPath (Join-Path $root $item) `
        -Destination $stage -Recurse -Force
}

$privateParameters = Join-Path $stage 'infra\main.parameters.json'
if (Test-Path -LiteralPath $privateParameters) {
    Remove-Item -LiteralPath $privateParameters -Force
}

if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}
Compress-Archive -Path (Join-Path $stage '*') `
    -DestinationPath $archive -CompressionLevel Optimal

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $archive
$hashLine = "$($hash.Hash.ToLowerInvariant())  $($hash.Path | Split-Path -Leaf)"
Set-Content -LiteralPath "$archive.sha256" -Value $hashLine -Encoding ascii
Remove-Item -LiteralPath $stage -Recurse -Force

Write-Host "Created $archive"
Write-Host "SHA256 $($hash.Hash)"
