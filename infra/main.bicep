targetScope = 'subscription'

@description('Short application name used in resource group and resource names.')
@minLength(2)
@maxLength(20)
param appName string

@description('Environment name such as dev, test, or prod.')
@minLength(2)
@maxLength(12)
param environmentName string

@description('Primary Azure region for application resources.')
param location string

@allowed([
  'public'
  'private'
])
@description('Public creates no private endpoints. Private integrates with existing PBMM or ALZ networking.')
param networkMode string = 'public'

@allowed([
  'none'
  'new'
  'existing'
])
@description('Monitoring lifecycle mode.')
param monitoringMode string = 'new'

@description('Existing network resource IDs required only in private mode.')
param privateNetwork object = {
  privateEndpointSubnetId: ''
  webIntegrationSubnetId: ''
  logicIntegrationSubnetId: ''
  privateDnsZoneIds: {}
}

@description('Existing monitoring values required only when monitoringMode is existing.')
param existingMonitoring object = {
  applicationInsightsConnectionString: ''
  logAnalyticsWorkspaceId: ''
  azureMonitorPrivateLinkScopeId: ''
}

@description('Optional resource group name overrides.')
param resourceGroupNames object = {
  application: ''
  ai: ''
  operations: ''
}

@description('Tags applied to deployed resources.')
param tags object = {}

param modelName string = 'gpt-4.1-mini'
param modelVersion string = '2025-04-14'
param modelSkuName string = 'GlobalStandard'
param modelCapacity int = 10
param backendApiAudience string = 'api://logic-app-ai-accelerator'

var privateMode = networkMode == 'private'
var normalizedAppName = toLower(replace(appName, '-', ''))
var resourceToken = take(
  '${normalizedAppName}${toLower(environmentName)}${uniqueString(subscription().id, appName, environmentName, location)}',
  20
)
var applicationResourceGroupName = !empty(resourceGroupNames.application)
  ? resourceGroupNames.application
  : 'rg-${appName}-${environmentName}'
var aiResourceGroupName = !empty(resourceGroupNames.ai)
  ? resourceGroupNames.ai
  : 'rg-${appName}-ai-${environmentName}'
var operationsResourceGroupName = !empty(resourceGroupNames.operations)
  ? resourceGroupNames.operations
  : 'rg-${appName}-ops-${environmentName}'
var commonTags = union(tags, {
  Application: appName
  Environment: environmentName
  ManagedBy: 'Bicep'
  Repository: 'logic-app-ai-accelerator'
})

var privateEndpointSubnetId = !privateMode
  ? ''
  : !empty(privateNetwork.?privateEndpointSubnetId ?? '')
    ? privateNetwork.privateEndpointSubnetId
    : fail('privateNetwork.privateEndpointSubnetId is required in private mode.')
var webIntegrationSubnetId = !privateMode
  ? ''
  : !empty(privateNetwork.?webIntegrationSubnetId ?? '')
    ? privateNetwork.webIntegrationSubnetId
    : fail('privateNetwork.webIntegrationSubnetId is required in private mode.')
var logicIntegrationSubnetId = !privateMode
  ? ''
  : !empty(privateNetwork.?logicIntegrationSubnetId ?? '')
    ? privateNetwork.logicIntegrationSubnetId
    : fail('privateNetwork.logicIntegrationSubnetId is required in private mode.')

var subnetsAreDistinct = privateEndpointSubnetId != webIntegrationSubnetId && privateEndpointSubnetId != logicIntegrationSubnetId && webIntegrationSubnetId != logicIntegrationSubnetId
var distinctPrivateSubnets = !privateMode
  ? true
  : subnetsAreDistinct ? true : fail('Private endpoint, web integration, and Logic App integration subnets must be separate.')

var suppliedDnsZoneIds = privateNetwork.?privateDnsZoneIds ?? {}
var privateDnsZoneIds = !privateMode
  ? {}
  : {
      blob: !empty(suppliedDnsZoneIds.?blob ?? '') ? suppliedDnsZoneIds.blob : fail('Private DNS zone blob is required.')
      file: !empty(suppliedDnsZoneIds.?file ?? '') ? suppliedDnsZoneIds.file : fail('Private DNS zone file is required.')
      queue: !empty(suppliedDnsZoneIds.?queue ?? '') ? suppliedDnsZoneIds.queue : fail('Private DNS zone queue is required.')
      table: !empty(suppliedDnsZoneIds.?table ?? '') ? suppliedDnsZoneIds.table : fail('Private DNS zone table is required.')
      cosmosSql: !empty(suppliedDnsZoneIds.?cosmosSql ?? '') ? suppliedDnsZoneIds.cosmosSql : fail('Private DNS zone cosmosSql is required.')
      acr: !empty(suppliedDnsZoneIds.?acr ?? '') ? suppliedDnsZoneIds.acr : fail('Private DNS zone acr is required.')
      sites: !empty(suppliedDnsZoneIds.?sites ?? '') ? suppliedDnsZoneIds.sites : fail('Private DNS zone sites is required.')
      cognitiveServices: !empty(suppliedDnsZoneIds.?cognitiveServices ?? '') ? suppliedDnsZoneIds.cognitiveServices : fail('Private DNS zone cognitiveServices is required.')
      openAi: !empty(suppliedDnsZoneIds.?openAi ?? '') ? suppliedDnsZoneIds.openAi : fail('Private DNS zone openAi is required.')
      aiServices: !empty(suppliedDnsZoneIds.?aiServices ?? '') ? suppliedDnsZoneIds.aiServices : fail('Private DNS zone aiServices is required.')
      search: !empty(suppliedDnsZoneIds.?search ?? '') ? suppliedDnsZoneIds.search : fail('Private DNS zone search is required.')
      monitor: monitoringMode != 'new'
        ? ''
        : !empty(suppliedDnsZoneIds.?monitor ?? '') ? suppliedDnsZoneIds.monitor : fail('Private DNS zone monitor is required for new private monitoring.')
      oms: monitoringMode != 'new'
        ? ''
        : !empty(suppliedDnsZoneIds.?oms ?? '') ? suppliedDnsZoneIds.oms : fail('Private DNS zone oms is required for new private monitoring.')
      ods: monitoringMode != 'new'
        ? ''
        : !empty(suppliedDnsZoneIds.?ods ?? '') ? suppliedDnsZoneIds.ods : fail('Private DNS zone ods is required for new private monitoring.')
      agentsvc: monitoringMode != 'new'
        ? ''
        : !empty(suppliedDnsZoneIds.?agentsvc ?? '') ? suppliedDnsZoneIds.agentsvc : fail('Private DNS zone agentsvc is required for new private monitoring.')
    }

var existingApplicationInsightsConnectionString = monitoringMode != 'existing'
  ? ''
  : !empty(existingMonitoring.?applicationInsightsConnectionString ?? '')
    ? existingMonitoring.applicationInsightsConnectionString
    : fail('existingMonitoring.applicationInsightsConnectionString is required in existing mode.')
var existingLogAnalyticsWorkspaceId = monitoringMode != 'existing'
  ? ''
  : !empty(existingMonitoring.?logAnalyticsWorkspaceId ?? '')
    ? existingMonitoring.logAnalyticsWorkspaceId
    : fail('existingMonitoring.logAnalyticsWorkspaceId is required in existing mode.')

resource applicationResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: applicationResourceGroupName
  location: location
  tags: commonTags
}

resource aiResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: aiResourceGroupName
  location: location
  tags: commonTags
}

resource operationsResourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = if (monitoringMode == 'new') {
  name: operationsResourceGroupName
  location: location
  tags: commonTags
}

module data './modules/application/data.bicep' = {
  name: 'application-data'
  scope: applicationResourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: commonTags
    networkMode: networkMode
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneIds: privateDnsZoneIds
  }
}

module monitoring './modules/monitoring/stack.bicep' = if (monitoringMode == 'new') {
  name: 'monitoring'
  scope: operationsResourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: commonTags
    networkMode: networkMode
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneIds: privateDnsZoneIds
  }
}

module ai './modules/ai/stack.bicep' = {
  name: 'ai-stack'
  scope: aiResourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: commonTags
    networkMode: networkMode
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneIds: privateDnsZoneIds
    storageName: data.outputs.storageName
    storageId: data.outputs.storageId
    storageBlobEndpoint: data.outputs.storageBlobEndpoint
    cosmosName: data.outputs.cosmosName
    cosmosId: data.outputs.cosmosId
    cosmosEndpoint: data.outputs.cosmosEndpoint
    modelName: modelName
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
  }
}

var applicationInsightsConnectionString = monitoringMode == 'new'
  ? monitoring!.outputs.applicationInsightsConnectionString
  : existingApplicationInsightsConnectionString
var logAnalyticsWorkspaceId = monitoringMode == 'new'
  ? monitoring!.outputs.workspaceId
  : existingLogAnalyticsWorkspaceId

module compute './modules/application/compute.bicep' = {
  name: 'application-compute'
  scope: applicationResourceGroup
  params: {
    location: location
    resourceToken: resourceToken
    tags: commonTags
    networkMode: networkMode
    privateEndpointSubnetId: privateEndpointSubnetId
    webIntegrationSubnetId: distinctPrivateSubnets ? webIntegrationSubnetId : ''
    logicIntegrationSubnetId: logicIntegrationSubnetId
    privateDnsZoneIds: privateDnsZoneIds
    storageBlobEndpoint: data.outputs.storageBlobEndpoint
    logicStorageId: data.outputs.logicStorageId
    cosmosEndpoint: data.outputs.cosmosEndpoint
    registryLoginServer: data.outputs.registryLoginServer
    foundryOpenAiEndpoint: ai.outputs.foundryOpenAiEndpoint
    documentIntelligenceEndpoint: ai.outputs.documentIntelligenceEndpoint
    searchEndpoint: ai.outputs.searchEndpoint
    modelDeploymentName: ai.outputs.modelDeploymentName
    monitoringMode: monitoringMode
    applicationInsightsConnectionString: applicationInsightsConnectionString
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    backendApiAudience: backendApiAudience
  }
}

module webAppRoles './modules/shared/role-assignment.bicep' = [
  for role in [
    {
      id: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
      name: 'acr-pull'
    }
    {
      id: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
      name: 'storage-blob-contributor'
    }
  ]: {
    name: 'web-${role.name}'
    scope: applicationResourceGroup
    params: {
      principalId: compute.outputs.webPrincipalId
      roleDefinitionId: role.id
      seed: role.name
    }
  }
]

module webAiRoles './modules/shared/role-assignment.bicep' = [
  for role in [
    {
      id: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
      name: 'openai-user'
    }
    {
      id: 'a97b65f3-24c7-4388-baec-2e87135dc908'
      name: 'cognitive-services-user'
    }
    {
      id: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
      name: 'search-index-contributor'
    }
  ]: {
    name: 'web-${role.name}'
    scope: aiResourceGroup
    params: {
      principalId: compute.outputs.webPrincipalId
      roleDefinitionId: role.id
      seed: role.name
    }
  }
]

module logicAppRoles './modules/shared/role-assignment.bicep' = [
  for role in [
    {
      id: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
      name: 'blob-contributor'
    }
    {
      id: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
      name: 'queue-contributor'
    }
    {
      id: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
      name: 'table-contributor'
    }
    {
      id: '69566ab7-960f-475b-8e7c-b3118f30c6bd'
      name: 'file-contributor'
    }
  ]: {
    name: 'logic-${role.name}'
    scope: applicationResourceGroup
    params: {
      principalId: compute.outputs.logicPrincipalId
      roleDefinitionId: role.id
      seed: role.name
    }
  }
]

module foundryProjectAppRoles './modules/shared/role-assignment.bicep' = [
  for role in [
    {
      id: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
      name: 'storage-blob-contributor'
    }
    {
      id: '230815da-be43-4aae-9cb4-875f7bd000aa'
      name: 'cosmos-operator'
    }
  ]: {
    name: 'foundry-project-${role.name}'
    scope: applicationResourceGroup
    params: {
      principalId: ai.outputs.foundryProjectPrincipalId
      roleDefinitionId: role.id
      seed: role.name
    }
  }
]

module foundryProjectAiRoles './modules/shared/role-assignment.bicep' = [
  for role in [
    {
      id: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
      name: 'search-index-contributor'
    }
    {
      id: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
      name: 'search-service-contributor'
    }
  ]: {
    name: 'foundry-project-${role.name}'
    scope: aiResourceGroup
    params: {
      principalId: ai.outputs.foundryProjectPrincipalId
      roleDefinitionId: role.id
      seed: role.name
    }
  }
]

module webCosmosDataRole './modules/shared/cosmos-data-role.bicep' = {
  name: 'web-cosmos-data-role'
  scope: applicationResourceGroup
  params: {
    accountName: data.outputs.cosmosName
    principalId: compute.outputs.webPrincipalId
  }
}

output applicationResourceGroupName string = applicationResourceGroup.name
output aiResourceGroupName string = aiResourceGroup.name
output operationsResourceGroupName string = monitoringMode == 'new' ? operationsResourceGroup.name : ''
output webAppName string = compute.outputs.webName
output webAppUri string = compute.outputs.webUri
output logicAppName string = compute.outputs.logicName
output foundryAccountName string = ai.outputs.foundryName
output foundryProjectId string = ai.outputs.foundryProjectId
output documentIntelligenceEndpoint string = ai.outputs.documentIntelligenceEndpoint
output searchEndpoint string = ai.outputs.searchEndpoint
output containerRegistryName string = data.outputs.registryName
