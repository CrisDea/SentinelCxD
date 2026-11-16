$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$buildScript = Join-Path $PSScriptRoot 'Build-Pack.ps1'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $buildScript, [ref]$tokens, [ref]$errors
)
if ($errors.Count -gt 0) { throw 'Build script could not be parsed.' }
$versionParameter = $ast.ParamBlock.Parameters |
    Where-Object { $_.Name.VariablePath.UserPath -eq 'Version' }
$validation = $versionParameter.Attributes |
    Where-Object { $_.TypeName.Name -eq 'ValidatePattern' }
if ($null -eq $validation) { throw 'Build version must have a validation pattern.' }
$pattern = $validation.PositionalArguments[0].Value

$workflow = Get-Content -Raw (Join-Path $root '..\.github\workflows\release.yml')
$match = [regex]::Match($workflow, '(?m)^        run: \|\r?\n(?<body>(?:          [^\r\n]*(?:\r?\n|$))+)')
if (-not $match.Success) { throw 'Release version step not found.' }
$body = ($match.Groups['body'].Value -split '\r?\n' |
    ForEach-Object { $_ -replace '^          ', '' }) -join "`n"
$outputLine = '"value=$version" >> $env:GITHUB_OUTPUT'
if (-not $body.Contains($outputLine)) { throw 'Release version output not found.' }
$resolveVersion = [scriptblock]::Create($body.Replace($outputLine, 'return $version'))

$previousTag = $env:TAG_NAME
try {
    foreach ($case in @(
        @{ Version = '1.2.3'; Valid = $true }
        @{ Version = '0.0.0'; Valid = $true }
        @{ Version = '01.2.3'; Valid = $false }
        @{ Version = '1.02.3'; Valid = $false }
        @{ Version = '../other'; Valid = $false }
        @{ Version = '1.2.3/../../other'; Valid = $false }
        @{ Version = 'v1.2.3'; Valid = $false }
        @{ Version = '1.2.3-beta'; Valid = $false }
        @{ Version = "1.2.3`n"; Valid = $false }
    )) {
        $version = $case.Version
        if (($version -cmatch $pattern) -ne $case.Valid) {
            throw "Unexpected build version validation for '$version'."
        }
        if (-not $case.Valid) {
            $rejected = $false
            try { & $buildScript -Version $version }
            catch {
                if ($_.FullyQualifiedErrorId -notlike 'ParameterArgumentValidationError,*') {
                    throw
                }
                $rejected = $true
            }
            if (-not $rejected) { throw "Build accepted invalid version '$version'." }
        }
        $env:TAG_NAME = "v$version"
        $accepted = $true
        try { $resolved = & $resolveVersion } catch { $accepted = $false }
        if ($accepted -ne $case.Valid -or
            ($accepted -and $resolved -cne $version)) {
            throw "Unexpected release tag validation for '$env:TAG_NAME'."
        }
    }
}
finally {
    $env:TAG_NAME = $previousTag
}
Write-Host 'Release version validation passed.'
