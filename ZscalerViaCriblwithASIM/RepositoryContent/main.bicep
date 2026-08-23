targetScope = 'resourceGroup'

@description('Microsoft Sentinel workspace name supplied by the Sentinel Repositories deployment workflow.')
param workspace string

@description('Create the canonical Cribl table, DCE, and DCR.')
param createIngestionLandingZone bool = true

@description('Optional object ID for the Cribl workload identity.')
param criblPrincipalObjectId string = ''

@description('DCE public network access. Disable only after private connectivity is ready.')
@allowed([
  'Enabled'
  'Disabled'
])
param criblPublicNetworkAccess string = 'Enabled'

@description('Canonical Zscaler Cribl table retention in days.')
@minValue(30)
@maxValue(730)
param criblTableRetentionInDays int = 90

@description('Send Key Vault and Logic App platform diagnostics to the workspace.')
param diagnosticSettingsEnabled bool = true

module contentPack '../infra/main.bicep' = {
  name: 'deploy-zscaler-via-cribl-asim'
  params: {
    workspaceName: workspace
    createIngestionLandingZone: createIngestionLandingZone
    criblPrincipalObjectId: criblPrincipalObjectId
    criblPublicNetworkAccess: criblPublicNetworkAccess
    criblTableRetentionInDays: criblTableRetentionInDays
    diagnosticSettingsEnabled: diagnosticSettingsEnabled
    workflowState: 'Disabled'
    operationWorkflowState: 'Disabled'
    enableZiaMutatingOperations: false
    automationRuleEnabled: false
  }
}

output criblLogsIngestionEndpoint string = contentPack.outputs.criblLogsIngestionEndpoint
output criblDcrImmutableId string = contentPack.outputs.criblDcrImmutableId
output criblStreamName string = contentPack.outputs.criblStreamName
output packIdentity string = contentPack.outputs.packIdentity
output workspaceResourceId string = contentPack.outputs.workspaceResourceId
output createdIngestionLandingZone bool = contentPack.outputs.createdIngestionLandingZone
output criblCanonicalTableResourceId string = contentPack.outputs.criblCanonicalTableResourceId
output criblDataCollectionRuleResourceId string = contentPack.outputs.criblDataCollectionRuleResourceId
output criblDataCollectionEndpointResourceId string = contentPack.outputs.criblDataCollectionEndpointResourceId
output keyVaultResourceId string = contentPack.outputs.keyVaultResourceId
output playbookResourceId string = contentPack.outputs.playbookResourceId
output operationPlaybookResourceId string = contentPack.outputs.operationPlaybookResourceId
output sentinelConnectionResourceId string = contentPack.outputs.sentinelConnectionResourceId
output incidentTeamsConnectionResourceId string = contentPack.outputs.incidentTeamsConnectionResourceId
output operationTeamsConnectionResourceId string = contentPack.outputs.operationTeamsConnectionResourceId
output keyVaultDiagnosticSettingResourceId string = contentPack.outputs.keyVaultDiagnosticSettingResourceId
output playbookDiagnosticSettingResourceId string = contentPack.outputs.playbookDiagnosticSettingResourceId
output operationPlaybookDiagnosticSettingResourceId string = contentPack.outputs.operationPlaybookDiagnosticSettingResourceId
output packOwnedParserResourceIds array = contentPack.outputs.packOwnedParserResourceIds
output sharedCustomParserResourceIds array = contentPack.outputs.sharedCustomParserResourceIds
output packOwnedRoleAssignmentResourceIds array = contentPack.outputs.packOwnedRoleAssignmentResourceIds
output criblRoleAssignmentResourceId string = contentPack.outputs.criblRoleAssignmentResourceId
output analyticRuleResourceIds array = contentPack.outputs.analyticRuleResourceIds
output huntingQueryResourceIds array = contentPack.outputs.huntingQueryResourceIds
output workbookResourceIds array = contentPack.outputs.workbookResourceIds
output automationRuleResourceId string = contentPack.outputs.automationRuleResourceId
