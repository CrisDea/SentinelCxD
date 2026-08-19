#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$SubscriptionId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkspaceName,

    [string]$ApproverUpn = 'securityanalyst@contoso.com',
    [string]$SentinelAutomationPrincipalId = '',
    [string]$CriblPrincipalObjectId = '',
    [ValidateRange(30, 730)]
    [int]$CriblTableRetentionInDays = 90,
    [ValidateSet('Enabled', 'Disabled')]
    [string]$CriblPublicNetworkAccess = 'Enabled',
    [bool]$CreateIngestionLandingZone = $true,
    [bool]$AnalyticsRulesEnabled = $true,
    [string]$DeploymentName = 'zscaler-via-cribl-asim',
    [switch]$SkipWhatIf
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$template = Join-Path $root 'Package\mainTemplate.json'

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required. Install it from https://aka.ms/installazurecliwindows.'
}
if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
    throw "Compiled ARM template not found: $template"
}

& az account show --only-show-errors --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Azure CLI is not authenticated. Run az login and retry.'
}

& az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select subscription '$SubscriptionId'."
}

& az group show --name $ResourceGroup --only-show-errors --output none
if ($LASTEXITCODE -ne 0) {
    throw "Resource group '$ResourceGroup' does not exist."
}

& az monitor log-analytics workspace show `
    --resource-group $ResourceGroup `
    --workspace-name $WorkspaceName `
    --only-show-errors `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw "Log Analytics workspace '$WorkspaceName' was not found in '$ResourceGroup'."
}

$templateParameters = @(
    "workspaceName=$WorkspaceName"
    "approverUpn=$ApproverUpn"
    "createIngestionLandingZone=$($CreateIngestionLandingZone.ToString().ToLowerInvariant())"
    "criblTableRetentionInDays=$CriblTableRetentionInDays"
    "criblPublicNetworkAccess=$CriblPublicNetworkAccess"
    "analyticsRulesEnabled=$($AnalyticsRulesEnabled.ToString().ToLowerInvariant())"
    'workflowState=Disabled'
    'operationWorkflowState=Disabled'
    'enableZiaMutatingOperations=false'
    'automationRuleEnabled=false'
)
if (-not [string]::IsNullOrWhiteSpace($SentinelAutomationPrincipalId)) {
    $templateParameters += "sentinelAutomationPrincipalId=$SentinelAutomationPrincipalId"
}
if (-not [string]::IsNullOrWhiteSpace($CriblPrincipalObjectId)) {
    $templateParameters += "criblPrincipalObjectId=$CriblPrincipalObjectId"
}

Write-Host 'Validating deployment...'
& az deployment group validate `
    --resource-group $ResourceGroup `
    --name "$DeploymentName-validate" `
    --template-file $template `
    --parameters $templateParameters `
    --only-show-errors `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw 'Azure deployment validation failed.'
}

if (-not $SkipWhatIf) {
    Write-Host 'Running resource-level what-if...'
    $whatIfJson = & az deployment group what-if `
        --resource-group $ResourceGroup `
        --name "$DeploymentName-whatif" `
        --template-file $template `
        --parameters $templateParameters `
        --result-format ResourceIdOnly `
        --no-pretty-print `
        --only-show-errors `
        --output json
    if ($LASTEXITCODE -ne 0) {
        throw 'Azure deployment what-if failed.'
    }

    $whatIf = $whatIfJson | ConvertFrom-Json
    $deletions = @($whatIf.changes | Where-Object { $_.changeType -eq 'Delete' })
    if ($deletions.Count -gt 0) {
        $ids = $deletions | ForEach-Object { $_.resourceId }
        throw "Deployment would delete resources:`n$($ids -join "`n")"
    }
}

Write-Host 'Deploying content pack with response automation disabled...'
$deploymentJson = & az deployment group create `
    --resource-group $ResourceGroup `
    --name $DeploymentName `
    --template-file $template `
    --parameters $templateParameters `
    --only-show-errors `
    --output json
if ($LASTEXITCODE -ne 0) {
    throw 'Azure deployment failed.'
}

$deployment = $deploymentJson | ConvertFrom-Json
if ($deployment.properties.provisioningState -ne 'Succeeded') {
    throw "Deployment finished in state '$($deployment.properties.provisioningState)'."
}

Write-Host 'Deployment succeeded.'
Write-Host "Cribl endpoint: $($deployment.properties.outputs.criblLogsIngestionEndpoint.value)"
Write-Host "DCR immutable ID: $($deployment.properties.outputs.criblDcrImmutableId.value)"
Write-Host "Cribl stream: $($deployment.properties.outputs.criblStreamName.value)"
