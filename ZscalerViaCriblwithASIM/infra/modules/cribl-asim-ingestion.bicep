targetScope = 'resourceGroup'

@description('Existing Microsoft Sentinel Log Analytics workspace name.')
param workspaceName string

@description('Azure region for the DCE and DCR. It must match the workspace region.')
param location string = resourceGroup().location

@description('Create the canonical table, DCE, DCR, and optional RBAC assignment. Set false only when compatible ingestion already targets ZscalerCribl_CL.')
param createIngestionLandingZone bool = true

@description('Existing Logs Ingestion endpoint when createIngestionLandingZone is false.')
param existingLogsIngestionEndpoint string = ''

@description('Existing DCR immutable ID when createIngestionLandingZone is false.')
param existingDcrImmutableId string = ''

@description('Existing DCR input stream when createIngestionLandingZone is false.')
param existingStreamName string = 'Custom-ZscalerCriblRaw'

@description('DCE resource name.')
param dataCollectionEndpointName string = 'dce-zscaler-cribl-${uniqueString(resourceGroup().id, workspaceName)}'

@description('DCR resource name.')
param dataCollectionRuleName string = 'dcr-zscaler-cribl-${uniqueString(resourceGroup().id, workspaceName)}'

@description('Retention for the canonical Analytics table.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 90

@description('Object ID of the Cribl workload identity. When supplied, Monitoring Metrics Publisher is assigned on the new DCR.')
param criblPrincipalObjectId string = ''

@description('Object type of the Cribl workload identity.')
@allowed([
  'ServicePrincipal'
  'User'
  'Group'
])
param criblPrincipalType string = 'ServicePrincipal'

@description('DCE public network access. Disable only when Cribl has private connectivity through Azure Monitor Private Link.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

var tableName = 'ZscalerCribl_CL'
var inputStreamName = 'Custom-ZscalerCriblRaw'
var outputStreamName = 'Custom-ZscalerCribl_CL'
var monitoringMetricsPublisherRoleId = '3913510d-42f4-4e42-8a64-420c390055eb'

var canonicalColumns = [
  { name: 'TimeGenerated', type: 'datetime' }
  { name: 'ZscalerFamily', type: 'string' }
  { name: 'ZscalerSubfamily', type: 'string' }
  { name: 'AsimSchemas', type: 'dynamic' }
  { name: 'EventVendor', type: 'string' }
  { name: 'EventProduct', type: 'string' }
  { name: 'EventProductVersion', type: 'string' }
  { name: 'EventType', type: 'string' }
  { name: 'EventSubType', type: 'string' }
  { name: 'EventResult', type: 'string' }
  { name: 'EventResultDetails', type: 'string' }
  { name: 'EventOriginalResultDetails', type: 'string' }
  { name: 'EventOriginalType', type: 'string' }
  { name: 'EventOriginalUid', type: 'string' }
  { name: 'EventUid', type: 'string' }
  { name: 'EventStartTime', type: 'datetime' }
  { name: 'EventEndTime', type: 'datetime' }
  { name: 'EventCount', type: 'long' }
  { name: 'EventSeverity', type: 'string' }
  { name: 'EventOriginalSeverity', type: 'string' }
  { name: 'EventMessage', type: 'string' }
  { name: 'RuleName', type: 'string' }
  { name: 'Operation', type: 'string' }
  { name: 'ActorUsername', type: 'string' }
  { name: 'ActorUsernameType', type: 'string' }
  { name: 'ActorUserId', type: 'string' }
  { name: 'Object', type: 'string' }
  { name: 'ObjectId', type: 'string' }
  { name: 'ObjectType', type: 'string' }
  { name: 'NewValue', type: 'string' }
  { name: 'OldValue', type: 'string' }
  { name: 'TargetUsername', type: 'string' }
  { name: 'TargetUsernameType', type: 'string' }
  { name: 'TargetUserId', type: 'string' }
  { name: 'TargetAppName', type: 'string' }
  { name: 'LogonMethod', type: 'string' }
  { name: 'AuthenticationProtocol', type: 'string' }
  { name: 'SrcIpAddr', type: 'string' }
  { name: 'SrcPortNumber', type: 'int' }
  { name: 'SrcNatIpAddr', type: 'string' }
  { name: 'SrcNatPortNumber', type: 'int' }
  { name: 'SrcUsername', type: 'string' }
  { name: 'SrcUsernameType', type: 'string' }
  { name: 'SrcUserId', type: 'string' }
  { name: 'SrcHostname', type: 'string' }
  { name: 'SrcGeoCountry', type: 'string' }
  { name: 'SrcGeoCity', type: 'string' }
  { name: 'DstIpAddr', type: 'string' }
  { name: 'DstPortNumber', type: 'int' }
  { name: 'DstNatIpAddr', type: 'string' }
  { name: 'DstNatPortNumber', type: 'int' }
  { name: 'DstUsername', type: 'string' }
  { name: 'DstUsernameType', type: 'string' }
  { name: 'DstUserId', type: 'string' }
  { name: 'DstHostname', type: 'string' }
  { name: 'DstFQDN', type: 'string' }
  { name: 'DstGeoCountry', type: 'string' }
  { name: 'DstGeoCity', type: 'string' }
  { name: 'DstAppName', type: 'string' }
  { name: 'DstAppType', type: 'string' }
  { name: 'DvcHostname', type: 'string' }
  { name: 'DvcIpAddr', type: 'string' }
  { name: 'DvcAction', type: 'string' }
  { name: 'NetworkProtocol', type: 'string' }
  { name: 'NetworkApplicationProtocol', type: 'string' }
  { name: 'NetworkDirection', type: 'string' }
  { name: 'NetworkDuration', type: 'long' }
  { name: 'NetworkBytes', type: 'long' }
  { name: 'SrcBytes', type: 'long' }
  { name: 'DstBytes', type: 'long' }
  { name: 'NetworkSessionId', type: 'string' }
  { name: 'NetworkRuleName', type: 'string' }
  { name: 'Url', type: 'string' }
  { name: 'UrlCategory', type: 'string' }
  { name: 'HttpRequestMethod', type: 'string' }
  { name: 'HttpStatusCode', type: 'int' }
  { name: 'HttpUserAgent', type: 'string' }
  { name: 'HttpReferrer', type: 'string' }
  { name: 'HttpContentType', type: 'string' }
  { name: 'DnsQuery', type: 'string' }
  { name: 'DnsQueryTypeName', type: 'string' }
  { name: 'DnsResponseCodeName', type: 'string' }
  { name: 'DnsResponseName', type: 'dynamic' }
  { name: 'DnsNetworkDuration', type: 'int' }
  { name: 'TargetFilePath', type: 'string' }
  { name: 'TargetFileName', type: 'string' }
  { name: 'TargetFileExtension', type: 'string' }
  { name: 'TargetFileMD5', type: 'string' }
  { name: 'TargetFileSHA1', type: 'string' }
  { name: 'TargetFileSHA256', type: 'string' }
  { name: 'TargetFileSHA512', type: 'string' }
  { name: 'TargetFileSize', type: 'long' }
  { name: 'TargetFileContentType', type: 'string' }
  { name: 'TargetFileCreationTime', type: 'datetime' }
  { name: 'TargetFileModificationTime', type: 'datetime' }
  { name: 'TargetFileOwner', type: 'string' }
  { name: 'SrcFilePath', type: 'string' }
  { name: 'SrcFileName', type: 'string' }
  { name: 'ThreatName', type: 'string' }
  { name: 'ThreatCategory', type: 'string' }
  { name: 'ThreatRiskLevel', type: 'string' }
  { name: 'AdditionalFields', type: 'dynamic' }
  { name: 'RawEvent', type: 'dynamic' }
]

var parserDefinitions = [
  {
    alias: 'vimZscalerCriblAuditEvent'
    displayName: 'Zscaler Cribl AuditEvent ASIM source parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),srcipaddr_has_any_prefix:dynamic=dynamic([]),actorusername_has_any:dynamic=dynamic([]),operation_has_any:dynamic=dynamic([]),eventtype_in:dynamic=dynamic([]),eventresult:string=\'*\',object_has_any:dynamic=dynamic([]),newvalue_has_any:dynamic=dynamic([]),disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/vimZscalerCriblAuditEvent.kql')
  }
  {
    alias: 'vimZscalerCriblAuthentication'
    displayName: 'Zscaler Cribl Authentication ASIM source parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),targetusername_has_any:dynamic=dynamic([]),actorusername_has_any:dynamic=dynamic([]),srcipaddr_has_any_prefix:dynamic=dynamic([]),srchostname_has_any:dynamic=dynamic([]),targetipaddr_has_any_prefix:dynamic=dynamic([]),dvcipaddr_has_any_prefix:dynamic=dynamic([]),dvchostname_has_any:dynamic=dynamic([]),eventtype_in:dynamic=dynamic([]),eventresultdetails_in:dynamic=dynamic([]),eventresult:string=\'*\',disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/vimZscalerCriblAuthentication.kql')
  }
  {
    alias: 'vimZscalerCriblDns'
    displayName: 'Zscaler Cribl DNS ASIM source parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),srcipaddr:string=\'*\',domain_has_any:dynamic=dynamic([]),responsecodename:string=\'*\',response_has_ipv4:string=\'*\',response_has_any_prefix:dynamic=dynamic([]),eventtype:string=\'Query\',disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/vimZscalerCriblDns.kql')
  }
  {
    alias: 'vimZscalerCriblFileEvent'
    displayName: 'Zscaler Cribl FileEvent ASIM source parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),eventtype_in:dynamic=dynamic([]),srcipaddr_has_any_prefix:dynamic=dynamic([]),actorusername_has_any:dynamic=dynamic([]),targetfilepath_has_any:dynamic=dynamic([]),srcfilepath_has_any:dynamic=dynamic([]),hashes_has_any:dynamic=dynamic([]),dvchostname_has_any:dynamic=dynamic([]),disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/vimZscalerCriblFileEvent.kql')
  }
  {
    alias: 'vimZscalerCriblNetworkSession'
    displayName: 'Zscaler Cribl NetworkSession ASIM source parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),srcipaddr_has_any_prefix:dynamic=dynamic([]),dstipaddr_has_any_prefix:dynamic=dynamic([]),ipaddr_has_any_prefix:dynamic=dynamic([]),dstportnumber:int=int(null),hostname_has_any:dynamic=dynamic([]),dvcaction:dynamic=dynamic([]),eventresult:string=\'*\',disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/vimZscalerCriblNetworkSession.kql')
  }
  {
    alias: 'vimZscalerCriblWebSession'
    displayName: 'Zscaler Cribl WebSession ASIM source parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),srcipaddr_has_any_prefix:dynamic=dynamic([]),ipaddr_has_any_prefix:dynamic=dynamic([]),url_has_any:dynamic=dynamic([]),httpuseragent_has_any:dynamic=dynamic([]),eventresultdetails_in:dynamic=dynamic([]),eventresult:string=\'*\',eventresultdetails_has_any:dynamic=dynamic([]),disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/vimZscalerCriblWebSession.kql')
  }
  {
    alias: 'Im_AuditEventCustom'
    displayName: 'Zscaler Cribl AuditEvent ASIM custom unifying parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),srcipaddr_has_any_prefix:dynamic=dynamic([]),actorusername_has_any:dynamic=dynamic([]),operation_has_any:dynamic=dynamic([]),eventtype_in:dynamic=dynamic([]),eventresult:string=\'*\',object_has_any:dynamic=dynamic([]),newvalue_has_any:dynamic=dynamic([]),disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/Im_AuditEventCustom.kql')
  }
  {
    alias: 'Im_AuthenticationCustom'
    displayName: 'Zscaler Cribl Authentication ASIM custom unifying parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),targetusername_has_any:dynamic=dynamic([]),actorusername_has_any:dynamic=dynamic([]),srcipaddr_has_any_prefix:dynamic=dynamic([]),srchostname_has_any:dynamic=dynamic([]),targetipaddr_has_any_prefix:dynamic=dynamic([]),dvcipaddr_has_any_prefix:dynamic=dynamic([]),dvchostname_has_any:dynamic=dynamic([]),eventtype_in:dynamic=dynamic([]),eventresultdetails_in:dynamic=dynamic([]),eventresult:string=\'*\',disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/Im_AuthenticationCustom.kql')
  }
  {
    alias: 'Im_DnsCustom'
    displayName: 'Zscaler Cribl DNS ASIM custom unifying parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),srcipaddr:string=\'*\',domain_has_any:dynamic=dynamic([]),responsecodename:string=\'*\',response_has_ipv4:string=\'*\',response_has_any_prefix:dynamic=dynamic([]),eventtype:string=\'Query\',disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/Im_DnsCustom.kql')
  }
  {
    alias: 'Im_FileEventCustom'
    displayName: 'Zscaler Cribl FileEvent ASIM custom unifying parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),eventtype_in:dynamic=dynamic([]),srcipaddr_has_any_prefix:dynamic=dynamic([]),actorusername_has_any:dynamic=dynamic([]),targetfilepath_has_any:dynamic=dynamic([]),srcfilepath_has_any:dynamic=dynamic([]),hashes_has_any:dynamic=dynamic([]),dvchostname_has_any:dynamic=dynamic([]),disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/Im_FileEventCustom.kql')
  }
  {
    alias: 'Im_NetworkSessionCustom'
    displayName: 'Zscaler Cribl NetworkSession ASIM custom unifying parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),srcipaddr_has_any_prefix:dynamic=dynamic([]),dstipaddr_has_any_prefix:dynamic=dynamic([]),ipaddr_has_any_prefix:dynamic=dynamic([]),dstportnumber:int=int(null),hostname_has_any:dynamic=dynamic([]),dvcaction:dynamic=dynamic([]),eventresult:string=\'*\',disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/Im_NetworkSessionCustom.kql')
  }
  {
    alias: 'Im_WebSessionCustom'
    displayName: 'Zscaler Cribl WebSession ASIM custom unifying parser'
    parameters: 'starttime:datetime=datetime(null),endtime:datetime=datetime(null),srcipaddr_has_any_prefix:dynamic=dynamic([]),ipaddr_has_any_prefix:dynamic=dynamic([]),url_has_any:dynamic=dynamic([]),httpuseragent_has_any:dynamic=dynamic([]),eventresultdetails_in:dynamic=dynamic([]),eventresult:string=\'*\',eventresultdetails_has_any:dynamic=dynamic([]),disabled:bool=false,pack:bool=false'
    query: loadTextContent('../../Parsers/Im_WebSessionCustom.kql')
  }
]

var sourceParserDefinitions = [
  parserDefinitions[0]
  parserDefinitions[1]
  parserDefinitions[2]
  parserDefinitions[3]
  parserDefinitions[4]
  parserDefinitions[5]
]

var customParserDefinitions = [
  parserDefinitions[6]
  parserDefinitions[7]
  parserDefinitions[8]
  parserDefinitions[9]
  parserDefinitions[10]
  parserDefinitions[11]
]

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource canonicalTable 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = if (createIngestionLandingZone) {
  parent: workspace
  name: tableName
  properties: {
    plan: 'Analytics'
    retentionInDays: retentionInDays
    totalRetentionInDays: retentionInDays
    schema: {
      name: tableName
      columns: canonicalColumns
    }
  }
}

resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = if (createIngestionLandingZone) {
  name: dataCollectionEndpointName
  location: location
  tags: {
    solution: 'Zscaler-ASIM-Cribl'
    component: 'logs-ingestion'
  }
  properties: {
    networkAcls: {
      publicNetworkAccess: publicNetworkAccess
    }
  }
}

resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2023-03-11' = if (createIngestionLandingZone) {
  name: dataCollectionRuleName
  location: location
  kind: 'Direct'
  tags: {
    solution: 'Zscaler-ASIM-Cribl'
    component: 'logs-ingestion'
  }
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    streamDeclarations: {
      'Custom-ZscalerCriblRaw': {
        columns: canonicalColumns
      }
    }
    destinations: {
      logAnalytics: [
        {
          name: 'zscalerCanonical'
          workspaceResourceId: workspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          inputStreamName
        ]
        destinations: [
          'zscalerCanonical'
        ]
        transformKql: 'source | extend EventVendor = "Zscaler"'
        outputStream: outputStreamName
      }
    ]
  }
  dependsOn: [
    canonicalTable
  ]
}

resource criblIngestionRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (createIngestionLandingZone && !empty(criblPrincipalObjectId)) {
  name: guid(dataCollectionRule.id, criblPrincipalObjectId, monitoringMetricsPublisherRoleId)
  scope: dataCollectionRule
  properties: {
    principalId: criblPrincipalObjectId
    principalType: criblPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringMetricsPublisherRoleId)
  }
}

resource sourceParsers 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = [
  for parser in sourceParserDefinitions: {
    parent: workspace
    name: parser.alias
    properties: {
      category: 'ASIM'
      displayName: parser.displayName
      functionAlias: parser.alias
      functionParameters: parser.parameters
      query: parser.query
      version: 1
    }
    dependsOn: [
      canonicalTable
    ]
  }
]

resource customUnifyingParsers 'Microsoft.OperationalInsights/workspaces/savedSearches@2020-08-01' = [
  for parser in customParserDefinitions: {
    parent: workspace
    name: parser.alias
    properties: {
      category: 'ASIM'
      displayName: parser.displayName
      functionAlias: parser.alias
      functionParameters: parser.parameters
      query: parser.query
      version: 1
    }
    dependsOn: [
      sourceParsers
    ]
  }
]

output canonicalTableName string = tableName
output logsIngestionEndpoint string = createIngestionLandingZone
  ? dataCollectionEndpoint!.properties.logsIngestion.endpoint
  : existingLogsIngestionEndpoint
output dcrImmutableId string = createIngestionLandingZone
  ? dataCollectionRule!.properties.immutableId
  : existingDcrImmutableId
output streamName string = createIngestionLandingZone ? inputStreamName : existingStreamName
output dataCollectionRuleResourceId string = createIngestionLandingZone ? dataCollectionRule!.id : ''
output sourceSpecificParserNames array = [
  'vimZscalerCriblAuditEvent'
  'vimZscalerCriblAuthentication'
  'vimZscalerCriblDns'
  'vimZscalerCriblFileEvent'
  'vimZscalerCriblNetworkSession'
  'vimZscalerCriblWebSession'
]
output customUnifyingParserNames array = [
  'Im_AuditEventCustom'
  'Im_AuthenticationCustom'
  'Im_DnsCustom'
  'Im_FileEventCustom'
  'Im_NetworkSessionCustom'
  'Im_WebSessionCustom'
]
