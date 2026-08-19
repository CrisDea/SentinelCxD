[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$workbookRoot = Join-Path $root 'Workbooks'
$generatedRoot = Join-Path $root 'infra\generated'
$outputPath = Join-Path $generatedRoot 'workbooks.json'

$definitions = @(
    @{
        File = 'ZscalerASIMOverview.json'
        Key = 'overview'
        DisplayName = 'Zscaler ASIM Overview and Cribl Health'
        Description = 'Zscaler ASIM coverage, top entities, and Cribl ingestion health.'
        Kind = 'consolidated'
        UpstreamFile = $null
    }
    @{
        File = 'ZscalerZIAWebDns.json'
        Key = 'zia-web-dns'
        DisplayName = 'Zscaler ZIA ASIM Web and DNS'
        Description = 'Consolidated ZIA web proxy and DNS activity normalized through ASIM.'
        Kind = 'consolidated'
        UpstreamFile = $null
    }
    @{
        File = 'ZscalerZIANetwork.json'
        Key = 'zia-network'
        DisplayName = 'Zscaler ZIA ASIM Network'
        Description = 'Consolidated ZIA firewall and tunnel activity normalized through ASIM.'
        Kind = 'consolidated'
        UpstreamFile = $null
    }
    @{
        File = 'ZscalerZPAAccess.json'
        Key = 'zpa-access'
        DisplayName = 'Zscaler ZPA ASIM Access'
        Description = 'ASIM-native parity workbook for the standard ZPA access workbook.'
        Kind = 'parity'
        UpstreamFile = 'ZscalerZPA.json'
    }
)

$ziaTitles = [ordered]@{
    'ZIA-Audit.json' = 'Zscaler ZIA ASIM - Audit Logs'
    'ZIA-CASB-Activity.json' = 'Zscaler ZIA ASIM - CASB Activity'
    'ZIA-CASB-Cloud-Storage.json' = 'Zscaler ZIA ASIM - CASB Cloud Storage'
    'ZIA-CASB-Collaboration.json' = 'Zscaler ZIA ASIM - CASB Collaboration'
    'ZIA-CASB-CRM.json' = 'Zscaler ZIA ASIM - CASB CRM'
    'ZIA-CASB-Email.json' = 'Zscaler ZIA ASIM - CASB Email'
    'ZIA-CASB-File-Sharing.json' = 'Zscaler ZIA ASIM - CASB File Sharing'
    'ZIA-CASB-ITSM.json' = 'Zscaler ZIA ASIM - CASB ITSM'
    'ZIA-CASB-Repository.json' = 'Zscaler ZIA ASIM - CASB Repository'
    'ZIA-DNS.json' = 'Zscaler ZIA ASIM - DNS'
    'ZIA-Email-DLP.json' = 'Zscaler ZIA ASIM - Email DLP'
    'ZIA-Endpoint-DLP.json' = 'Zscaler ZIA ASIM - Endpoint DLP'
    'ZIA-Firewall.json' = 'Zscaler ZIA ASIM - Firewall'
    'ZIA-Tunnel.json' = 'Zscaler ZIA ASIM - Tunnel'
    'ZIA-Office365.json' = 'Zscaler ZIA ASIM - Microsoft 365'
    'ZIA-Web-Overview.json' = 'Zscaler ZIA ASIM - Web Overview'
    'ZIA-Web-Threats.json' = 'Zscaler ZIA ASIM - Web Threats'
}

$ziaParityPath = Join-Path $workbookRoot 'zia-workbook-parity.json'
$ziaParity = Get-Content -LiteralPath $ziaParityPath -Raw |
    ConvertFrom-Json -Depth 100
if ($ziaParity.workbookCount -ne 17 -or $ziaParity.workbooks.Count -ne 17) {
    throw 'ZIA workbook parity manifest must contain exactly 17 workbooks.'
}

foreach ($mapping in $ziaParity.workbooks) {
    $file = [string]$mapping.workbookFile
    if (-not $ziaTitles.Contains($file)) {
        throw "Missing deployment title for ZIA workbook '$file'."
    }
    $definitions += @{
        File = $file
        Key = [IO.Path]::GetFileNameWithoutExtension($file).ToLowerInvariant()
        DisplayName = $ziaTitles[$file]
        Description = "ASIM-native parity workbook for standard ZIA workbook $($mapping.upstreamFile)."
        Kind = 'parity'
        UpstreamFile = [string]$mapping.upstreamFile
    }
}

$workbooks = foreach ($definition in $definitions) {
    $path = Join-Path $workbookRoot $definition.File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Workbook file not found: $path"
    }

    [ordered]@{
        key = $definition.Key
        displayName = $definition.DisplayName
        description = $definition.Description
        kind = $definition.Kind
        sourceFile = $definition.File
        upstreamFile = $definition.UpstreamFile
        serializedData = Get-Content -LiteralPath $path -Raw |
            ConvertFrom-Json -Depth 100
    }
}

New-Item -ItemType Directory -Force -Path $generatedRoot | Out-Null
$temporaryPath = "$outputPath.$([guid]::NewGuid().ToString('N')).tmp"
try {
    [ordered]@{
        schemaVersion = '1.0.0'
        workbookCount = $workbooks.Count
        workbooks = @($workbooks)
    } |
        ConvertTo-Json -Depth 100 |
        Set-Content -LiteralPath $temporaryPath -Encoding utf8NoBOM
    Move-Item -LiteralPath $temporaryPath -Destination $outputPath -Force
}
finally {
    if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
    }
}

Write-Host "Generated $outputPath with $($workbooks.Count) workbooks."
