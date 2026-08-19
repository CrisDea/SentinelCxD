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

module contentPack '../infra/main.bicep' = {
  name: 'deploy-zscaler-via-cribl-asim'
  params: {
    workspaceName: workspace
    createIngestionLandingZone: createIngestionLandingZone
    criblPrincipalObjectId: criblPrincipalObjectId
    criblPublicNetworkAccess: criblPublicNetworkAccess
    criblTableRetentionInDays: criblTableRetentionInDays
    workflowState: 'Disabled'
    operationWorkflowState: 'Disabled'
    enableZiaMutatingOperations: false
    automationRuleEnabled: false
  }
}

output criblLogsIngestionEndpoint string = contentPack.outputs.criblLogsIngestionEndpoint
output criblDcrImmutableId string = contentPack.outputs.criblDcrImmutableId
output criblStreamName string = contentPack.outputs.criblStreamName
