#requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
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

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DeploymentName,

    [switch]$RemoveIngestionLandingZone
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scriptCmdlet = $PSCmdlet

function Invoke-AzJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $json = & az @Arguments --only-show-errors --output json
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: az $($Arguments -join ' ')"
    }
    return $json | ConvertFrom-Json
}

function Test-AzResource {
    param([Parameter(Mandatory)][string]$ResourceId)

    & az resource show --ids $ResourceId --only-show-errors --output none 2>$null
    return $LASTEXITCODE -eq 0
}

function Remove-AzResource {
    param([AllowEmptyString()][string]$ResourceId)

    if ([string]::IsNullOrWhiteSpace($ResourceId) -or
        -not (Test-AzResource -ResourceId $ResourceId)) {
        return
    }

    if ($scriptCmdlet.ShouldProcess($ResourceId, 'Delete pack-owned resource')) {
        & az resource delete --ids $ResourceId --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to delete resource '$ResourceId'."
        }
    }
}

function Remove-AzRoleAssignment {
    param([AllowEmptyString()][string]$ResourceId)

    if ([string]::IsNullOrWhiteSpace($ResourceId)) {
        return
    }

    if ($scriptCmdlet.ShouldProcess(
            $ResourceId,
            'Delete pack-owned role assignment'
        )) {
        & az role assignment delete --ids $ResourceId --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to delete role assignment '$ResourceId'."
        }
    }
}

function Remove-AzDiagnosticSetting {
    param([AllowEmptyString()][string]$ResourceId)

    if ([string]::IsNullOrWhiteSpace($ResourceId)) {
        return
    }

    $marker = '/providers/Microsoft.Insights/diagnosticSettings/'
    $markerIndex = $ResourceId.LastIndexOf(
        $marker,
        [System.StringComparison]::OrdinalIgnoreCase
    )
    if ($markerIndex -lt 1) {
        throw "Invalid diagnostic setting resource ID '$ResourceId'."
    }

    $scope = $ResourceId.Substring(0, $markerIndex)
    $name = $ResourceId.Substring($markerIndex + $marker.Length)
    & az monitor diagnostic-settings show `
        --resource $scope `
        --name $name `
        --only-show-errors `
        --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        return
    }

    if ($scriptCmdlet.ShouldProcess(
            $ResourceId,
            'Delete pack-owned diagnostic setting'
        )) {
        & az monitor diagnostic-settings delete `
            --resource $scope `
            --name $name `
            --only-show-errors
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to delete diagnostic setting '$ResourceId'."
        }
    }
}

function Disable-AzAnalyticRule {
    param([AllowEmptyString()][string]$ResourceId)

    if ([string]::IsNullOrWhiteSpace($ResourceId) -or
        -not (Test-AzResource -ResourceId $ResourceId)) {
        return
    }

    if ($scriptCmdlet.ShouldProcess(
            $ResourceId,
            'Disable preserved analytic rule'
        )) {
        & az resource update `
            --ids $ResourceId `
            --api-version 2025-06-01 `
            --set properties.enabled=false `
            --only-show-errors `
            --output none
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to disable analytic rule '$ResourceId'."
        }
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required.'
}

& az account set --subscription $SubscriptionId
if ($LASTEXITCODE -ne 0) {
    throw "Unable to select subscription '$SubscriptionId'."
}

$deployment = Invoke-AzJson @(
    'deployment', 'group', 'show',
    '--resource-group', $ResourceGroup,
    '--name', $DeploymentName
)
if ($deployment.properties.provisioningState -ne 'Succeeded') {
    throw "Deployment '$DeploymentName' is not in Succeeded state."
}

$outputs = $deployment.properties.outputs
$requiredOutputs = @(
    'packIdentity'
    'workspaceResourceId'
    'createdIngestionLandingZone'
    'criblCanonicalTableResourceId'
    'criblDataCollectionRuleResourceId'
    'criblDataCollectionEndpointResourceId'
    'keyVaultResourceId'
    'playbookResourceId'
    'operationPlaybookResourceId'
    'sentinelConnectionResourceId'
    'incidentTeamsConnectionResourceId'
    'operationTeamsConnectionResourceId'
    'keyVaultDiagnosticSettingResourceId'
    'playbookDiagnosticSettingResourceId'
    'operationPlaybookDiagnosticSettingResourceId'
    'packOwnedParserResourceIds'
    'packOwnedRoleAssignmentResourceIds'
    'criblRoleAssignmentResourceId'
    'analyticRuleResourceIds'
    'huntingQueryResourceIds'
    'workbookResourceIds'
    'automationRuleResourceId'
)
$missingOutputs = @($requiredOutputs | Where-Object {
    $null -eq $outputs.PSObject.Properties[$_]
})
if ($missingOutputs.Count -gt 0) {
    throw "Deployment '$DeploymentName' is not a supported pack cleanup authority. Missing outputs: $($missingOutputs -join ', ')."
}
if ($outputs.packIdentity.value -ne
    'SentinelCxD/ZscalerViaCriblwithASIM/2.1') {
    throw "Deployment '$DeploymentName' has an unsupported pack identity."
}

$workspaceId = $outputs.workspaceResourceId.value
$expectedWorkspaceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$WorkspaceName"
if ($workspaceId -ine $expectedWorkspaceId) {
    throw "Workspace '$WorkspaceName' does not match deployment output '$workspaceId'."
}

$keyVaultId = $outputs.keyVaultResourceId.value
$dcrId = $outputs.criblDataCollectionRuleResourceId.value
$dceId = $outputs.criblDataCollectionEndpointResourceId.value

foreach ($resourceId in @($outputs.packOwnedRoleAssignmentResourceIds.value)) {
    Remove-AzRoleAssignment $resourceId
}

Remove-AzResource $outputs.automationRuleResourceId.value

foreach ($resourceId in @($outputs.analyticRuleResourceIds.value)) {
    Disable-AzAnalyticRule $resourceId
}
foreach ($resourceId in @($outputs.workbookResourceIds.value)) {
    Remove-AzResource $resourceId
}
foreach ($resourceId in @($outputs.huntingQueryResourceIds.value)) {
    Remove-AzResource $resourceId
}
foreach ($resourceId in @($outputs.packOwnedParserResourceIds.value)) {
    Remove-AzResource $resourceId
}

Remove-AzDiagnosticSetting $outputs.playbookDiagnosticSettingResourceId.value
Remove-AzDiagnosticSetting $outputs.operationPlaybookDiagnosticSettingResourceId.value
Remove-AzDiagnosticSetting $outputs.keyVaultDiagnosticSettingResourceId.value
Remove-AzResource $outputs.playbookResourceId.value
Remove-AzResource $outputs.operationPlaybookResourceId.value
Remove-AzResource $outputs.sentinelConnectionResourceId.value
Remove-AzResource $outputs.incidentTeamsConnectionResourceId.value
Remove-AzResource $outputs.operationTeamsConnectionResourceId.value

if ($RemoveIngestionLandingZone) {
    if (-not $outputs.createdIngestionLandingZone.value) {
        throw "Deployment '$DeploymentName' did not create the ingestion landing zone."
    }

    Remove-AzRoleAssignment $outputs.criblRoleAssignmentResourceId.value
    Remove-AzResource $dcrId
    Remove-AzResource $dceId
}

Write-Host 'Pack-owned content was removed.'
Write-Host "Key Vault preserved: $keyVaultId"
Write-Host "Canonical table and data preserved: $($outputs.criblCanonicalTableResourceId.value)"
