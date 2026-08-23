targetScope = 'resourceGroup'

@description('Existing Microsoft Sentinel Log Analytics workspace name.')
param workspaceName string

@description('Azure location for regional pack resources.')
param location string = resourceGroup().location

@description('Globally unique Key Vault name. Defaults to a deterministic name.')
@minLength(3)
@maxLength(24)
param keyVaultName string = 'kv-zscasim-${uniqueString(resourceGroup().id)}'

@description('Logic App playbook name.')
param playbookName string = 'Zscaler-ASIM-Incident-Response'

@description('Reusable ZIA operation Logic App name.')
param operationPlaybookName string = 'Zscaler-ZIA-Operation'

@description('Microsoft Sentinel API connection name.')
param sentinelConnectionName string = 'azuresentinel-zscaler-asim-response'

@description('Microsoft Teams API connection name.')
param teamsConnectionName string = 'teams-zscaler-asim-response'

@description('Microsoft Teams API connection name for the reusable operation workflow.')
param operationTeamsConnectionName string = 'teams-zscaler-zia-operation'

@description('UPN of the analyst who receives the Teams approval request.')
param approverUpn string = 'securityanalyst@contoso.com'

@description('Deploy analytic rules enabled.')
param analyticsRulesEnabled bool = false

@description('Optional rule-ID namespace for recovery from Sentinel deleted-rule tombstones. Leave empty for stable upstream rule IDs.')
param analyticRuleIdNamespace string = ''

@description('Logic App state. Keep Disabled until secrets and Teams are ready.')
@allowed([
  'Disabled'
  'Enabled'
])
param workflowState string = 'Disabled'

@description('Reusable ZIA operation Logic App state. Keep Disabled until caller authentication and controlled tests pass.')
@allowed([
  'Disabled'
  'Enabled'
])
param operationWorkflowState string = 'Disabled'

@description('Enable mutating operations in the reusable ZIA operation workflow. Keep false until approval testing passes.')
param enableZiaMutatingOperations bool = false

@description('Enable the Sentinel automation rule. Keep false until playbook testing passes.')
param automationRuleEnabled bool = false

@description('Optional tenant object ID for the Microsoft Sentinel service principal. Supply it before enabling automation.')
param sentinelAutomationPrincipalId string = ''

@description('Key Vault secret containing the Zscaler OneAPI client ID.')
param zscalerClientIdSecretName string = 'zscaler-oneapi-client-id'

@description('Key Vault secret containing the Zscaler OneAPI client secret.')
param zscalerClientSecretSecretName string = 'zscaler-oneapi-client-secret'

@description('Key Vault secret containing the Zscaler OAuth token URL.')
param zscalerTokenUrlSecretName string = 'zscaler-oneapi-token-url'

@description('Zscaler OneAPI base URI.')
param zscalerApiBaseUri string = 'https://api.zsapi.net'

@description('Zscaler ZIA cloud name used for response audit context.')
param zscalerCloudName string = ''

@description('Microsoft Entra token audience required by the reusable ZIA operation workflow.')
param operationTriggerAudience string = environment().resourceManager

@description('Zscaler ZIA URL category used for approved IP and URL blocks.')
param zscalerBlockCategory string = 'OTHER_MISCELLANEOUS'

@description('Approval timeout in ISO 8601 format.')
param approvalTimeout string = 'PT8H'

@description('ASIM enrichment lookback in days.')
@minValue(1)
@maxValue(30)
param asimTimeRangeDays int = 7

@description('Maximum rows returned per ASIM enrichment query.')
@minValue(1)
@maxValue(200)
param asimRowLimit int = 50

@description('Create the canonical Cribl table, DCE, and DCR. Parsers are always deployed.')
param createIngestionLandingZone bool = true

@description('Existing Logs Ingestion endpoint when createIngestionLandingZone is false.')
param existingLogsIngestionEndpoint string = ''

@description('Existing DCR immutable ID when createIngestionLandingZone is false.')
param existingDcrImmutableId string = ''

@description('Existing DCR stream name when createIngestionLandingZone is false.')
param existingCriblStreamName string = 'Custom-ZscalerCriblRaw'

@description('Canonical Zscaler Cribl table retention in days.')
@minValue(30)
@maxValue(730)
param criblTableRetentionInDays int = 90

@description('Optional object ID for the Cribl workload identity. Monitoring Metrics Publisher is assigned on the new DCR when supplied.')
param criblPrincipalObjectId string = ''

@description('Object type for the Cribl workload identity.')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param criblPrincipalType string = 'ServicePrincipal'

@description('DCE public network access. Disable only after Azure Monitor Private Link connectivity is ready.')
@allowed([
  'Enabled'
  'Disabled'
])
param criblPublicNetworkAccess string = 'Enabled'

@description('Send Key Vault and Logic App platform diagnostics to the target Log Analytics workspace.')
param diagnosticSettingsEnabled bool = true

var packIdentity = 'SentinelCxD/ZscalerViaCriblwithASIM/2.1'
var roleIds = {
  logAnalyticsReader: '73c42c96-874c-492b-b04d-ab87d138a893'
  sentinelResponder: '3e150937-b8fe-4cfb-8069-0eaf05ecd056'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  sentinelAutomationContributor: 'f4c81013-99ee-4d62-a7ee-b3f1f648599a'
}

var rules = loadJsonContent('../Analytic Rules/rules.json')
var analyticRuleResourceNames = [
  for rule in rules: empty(analyticRuleIdNamespace)
    ? rule.id
    : guid(workspace.id, analyticRuleIdNamespace, rule.id)
]
var huntingQueries = loadJsonContent('../Hunting Queries/hunting-queries.json').queries
var workbookDefinitions = loadJsonContent('generated/workbooks.json').workbooks

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

module criblAsim 'modules/cribl-asim-ingestion.bicep' = {
  name: 'deploy-zscaler-cribl-asim-ingestion'
  params: {
    workspaceName: workspaceName
    location: workspace.location
    createIngestionLandingZone: createIngestionLandingZone
    existingLogsIngestionEndpoint: existingLogsIngestionEndpoint
    existingDcrImmutableId: existingDcrImmutableId
    existingStreamName: existingCriblStreamName
    retentionInDays: criblTableRetentionInDays
    criblPrincipalObjectId: criblPrincipalObjectId
    criblPrincipalType: criblPrincipalType
    publicNetworkAccess: criblPublicNetworkAccess
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' = {
  name: keyVaultName
  location: location
  tags: {
    solution: 'Zscaler-ASIM-Cribl'
    component: 'playbook-secrets'
  }
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    accessPolicies: []
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

module playbook '../Playbooks/Zscaler-ASIM-Incident-Response/azuredeploy.json' = {
  name: 'deploy-zscaler-asim-playbook'
  params: {
    PlaybookName: playbookName
    SentinelConnectionName: sentinelConnectionName
    TeamsConnectionName: teamsConnectionName
    WorkflowState: workflowState
    LogAnalyticsWorkspaceId: workspace.properties.customerId
    KeyVaultUri: keyVault.properties.vaultUri
    ZscalerClientIdSecretName: zscalerClientIdSecretName
    ZscalerClientSecretSecretName: zscalerClientSecretSecretName
    ZscalerTokenUrlSecretName: zscalerTokenUrlSecretName
    ZscalerApiBaseUri: zscalerApiBaseUri
    ZscalerBlockCategory: zscalerBlockCategory
    ApproverUpn: approverUpn
    ApprovalTimeout: approvalTimeout
    AsimTimeRangeDays: asimTimeRangeDays
    AsimRowLimit: asimRowLimit
  }
}

module operationPlaybook '../Playbooks/Zscaler-ZIA-Operation/azuredeploy.json' = {
  name: 'deploy-zscaler-zia-operation-playbook'
  params: {
    PlaybookName: operationPlaybookName
    TeamsConnectionName: operationTeamsConnectionName
    WorkflowState: operationWorkflowState
    EnableMutatingOperations: enableZiaMutatingOperations
    AuthorizedCallerObjectId: playbook.outputs.principalId
    TriggerAudience: operationTriggerAudience
    ApproverUpn: approverUpn
    ApprovalTimeout: approvalTimeout
    KeyVaultUri: keyVault.properties.vaultUri
    ZscalerClientIdSecretName: zscalerClientIdSecretName
    ZscalerClientSecretSecretName: zscalerClientSecretSecretName
    ZscalerTokenUrlSecretName: zscalerTokenUrlSecretName
    ZscalerApiBaseUri: zscalerApiBaseUri
    ZscalerCloudName: zscalerCloudName
    IpBlockCategoryId: zscalerBlockCategory
    UrlBlockCategoryId: zscalerBlockCategory
  }
}

resource incidentWorkflow 'Microsoft.Logic/workflows@2019-05-01' existing = {
  name: playbookName
}

resource operationWorkflow 'Microsoft.Logic/workflows@2019-05-01' existing = {
  name: operationPlaybookName
}

resource keyVaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'zscaler-asim-monitoring'
  scope: keyVault
  properties: {
    workspaceId: workspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'AuditEvent'
        enabled: diagnosticSettingsEnabled
      }
      {
        category: 'AzurePolicyEvaluationDetails'
        enabled: diagnosticSettingsEnabled
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: diagnosticSettingsEnabled
      }
    ]
  }
}

resource incidentWorkflowDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'zscaler-asim-monitoring'
  scope: incidentWorkflow
  properties: {
    workspaceId: workspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: diagnosticSettingsEnabled
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: diagnosticSettingsEnabled
      }
    ]
  }
  dependsOn: [
    playbook
  ]
}

resource operationWorkflowDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'zscaler-asim-monitoring'
  scope: operationWorkflow
  properties: {
    workspaceId: workspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: diagnosticSettingsEnabled
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: diagnosticSettingsEnabled
      }
    ]
  }
  dependsOn: [
    operationPlaybook
  ]
}

resource analyticRules 'Microsoft.SecurityInsights/alertRules@2025-06-01' = [
  for (rule, index) in rules: {
    name: analyticRuleResourceNames[index]
    scope: workspace
    kind: 'Scheduled'
    properties: {
      displayName: rule.displayName
      description: rule.description
      enabled: analyticsRulesEnabled
      severity: rule.severity
      query: rule.query
      queryFrequency: rule.queryFrequency
      queryPeriod: rule.queryPeriod
      triggerOperator: rule.triggerOperator
      triggerThreshold: rule.triggerThreshold
      suppressionEnabled: rule.suppressionEnabled
      suppressionDuration: rule.suppressionDuration
      tactics: rule.tactics
      techniques: rule.techniques
      entityMappings: rule.entityMappings
      eventGroupingSettings: {
        aggregationKind: 'SingleAlert'
      }
      incidentConfiguration: {
        createIncident: true
        groupingConfiguration: {
          enabled: false
          reopenClosedIncident: false
          lookbackDuration: 'PT5H'
          matchingMethod: 'AllEntities'
          groupByEntities: []
          groupByAlertDetails: []
          groupByCustomDetails: []
        }
      }
    }
  }
]

resource huntingSearches 'Microsoft.OperationalInsights/workspaces/savedSearches@2022-10-01' = [
  for hunt in huntingQueries: {
    name: guid(workspace.id, 'zscaler-asim-hunt', hunt.id)
    parent: workspace
    properties: {
      eTag: '*'
      displayName: hunt.displayName
      category: 'Hunting Queries'
      query: hunt.query
      version: 2
      tags: [
        {
          name: 'description'
          value: take(hunt.description, 256)
        }
        {
          name: 'tactics'
          value: join(hunt.tactics, ',')
        }
        {
          name: 'techniques'
          value: join(hunt.techniques, ',')
        }
      ]
    }
  }
]

resource workbooks 'Microsoft.Insights/workbooks@2023-06-01' = [
  for workbook in workbookDefinitions: {
    name: guid(workspace.id, 'zscaler-asim-cribl', workbook.key)
    location: location
    kind: 'shared'
    tags: {
      solution: 'Zscaler-ASIM-Cribl'
      'hidden-title': workbook.displayName
    }
    properties: {
      displayName: workbook.displayName
      description: workbook.description
      category: 'sentinel'
      sourceId: workspace.id
      serializedData: string(workbook.serializedData)
      version: 'Notebook/1.0'
    }
  }
]

resource logAnalyticsReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, playbookName, roleIds.logAnalyticsReader)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleIds.logAnalyticsReader
    )
    principalId: playbook.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'Read ASIM-normalized Log Analytics data for Zscaler incident enrichment.'
  }
}

resource sentinelResponderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, playbookName, roleIds.sentinelResponder)
  scope: workspace
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleIds.sentinelResponder
    )
    principalId: playbook.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'Add enrichment and response results to Microsoft Sentinel incidents.'
  }
}

resource keyVaultSecretsAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, playbookName, roleIds.keyVaultSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleIds.keyVaultSecretsUser
    )
    principalId: playbook.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'Read Zscaler OAuth values from this Key Vault after analyst approval.'
  }
}

resource operationKeyVaultSecretsAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, operationPlaybookName, roleIds.keyVaultSecretsUser)
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleIds.keyVaultSecretsUser
    )
    principalId: operationPlaybook.outputs.principalId
    principalType: 'ServicePrincipal'
    description: 'Read Zscaler OAuth values for allowlisted ZIA response operations.'
  }
}

resource sentinelAutomationAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(sentinelAutomationPrincipalId)) {
  name: guid(resourceGroup().id, sentinelAutomationPrincipalId, roleIds.sentinelAutomationContributor)
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roleIds.sentinelAutomationContributor
    )
    principalId: sentinelAutomationPrincipalId
    principalType: 'ServicePrincipal'
    description: 'Allow Microsoft Sentinel to invoke playbooks in this resource group.'
  }
}

resource automationRule 'Microsoft.SecurityInsights/automationRules@2025-06-01' = {
  name: guid(workspace.id, 'Zscaler-ASIM-Incident-Response')
  scope: workspace
  properties: {
    displayName: 'Zscaler ASIM - Enrich and request block approval'
    order: 100
    triggeringLogic: {
      isEnabled: automationRuleEnabled
      triggersOn: 'Incidents'
      triggersWhen: 'Created'
      conditions: [
        {
          conditionType: 'Property'
          conditionProperties: {
            propertyName: 'IncidentRelatedAnalyticRuleIds'
            operator: 'Contains'
            propertyValues: [
              for (rule, index) in rules: extensionResourceId(
                workspace.id,
                'Microsoft.SecurityInsights/alertRules',
                analyticRuleResourceNames[index]
              )
            ]
          }
        }
      ]
    }
    actions: [
      {
        order: 1
        actionType: 'RunPlaybook'
        actionConfiguration: {
          logicAppResourceId: playbook.outputs.workflowResourceId
          tenantId: subscription().tenantId
        }
      }
    ]
  }
  dependsOn: [
    sentinelAutomationAssignment
  ]
}

output packIdentity string = packIdentity
output workspaceResourceId string = workspace.id
output createdIngestionLandingZone bool = createIngestionLandingZone
output criblCanonicalTableName string = criblAsim.outputs.canonicalTableName
output criblCanonicalTableResourceId string = criblAsim.outputs.canonicalTableResourceId
output criblLogsIngestionEndpoint string = criblAsim.outputs.logsIngestionEndpoint
output criblDcrImmutableId string = criblAsim.outputs.dcrImmutableId
output criblStreamName string = criblAsim.outputs.streamName
output criblDataCollectionRuleResourceId string = criblAsim.outputs.dataCollectionRuleResourceId
output criblDataCollectionEndpointResourceId string = criblAsim.outputs.dataCollectionEndpointResourceId
output keyVaultResourceId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
output playbookResourceId string = playbook.outputs.workflowResourceId
output playbookPrincipalId string = playbook.outputs.principalId
output sentinelConnectionResourceId string = playbook.outputs.sentinelConnectionResourceId
output incidentTeamsConnectionResourceId string = playbook.outputs.teamsConnectionResourceId
output operationPlaybookResourceId string = operationPlaybook.outputs.workflowResourceId
output operationPlaybookPrincipalId string = operationPlaybook.outputs.principalId
output operationTeamsConnectionResourceId string = operationPlaybook.outputs.teamsConnectionResourceId
output keyVaultDiagnosticSettingResourceId string = keyVaultDiagnostics.id
output playbookDiagnosticSettingResourceId string = incidentWorkflowDiagnostics.id
output operationPlaybookDiagnosticSettingResourceId string = operationWorkflowDiagnostics.id
output packOwnedParserResourceIds array = criblAsim.outputs.packOwnedParserResourceIds
output sharedCustomParserResourceIds array = criblAsim.outputs.sharedCustomParserResourceIds
output packOwnedRoleAssignmentResourceIds array = [
  logAnalyticsReaderAssignment.id
  sentinelResponderAssignment.id
  keyVaultSecretsAssignment.id
  operationKeyVaultSecretsAssignment.id
]
output criblRoleAssignmentResourceId string = criblAsim.outputs.criblRoleAssignmentResourceId
output analyticRuleResourceIds array = [
  for (rule, index) in rules: extensionResourceId(
    workspace.id,
    'Microsoft.SecurityInsights/alertRules',
    analyticRuleResourceNames[index]
  )
]
output huntingQueryResourceIds array = [for (hunt, index) in huntingQueries: huntingSearches[index].id]
output workbookResourceIds array = [for (workbook, index) in workbookDefinitions: workbooks[index].id]
output automationRuleResourceId string = automationRule.id
