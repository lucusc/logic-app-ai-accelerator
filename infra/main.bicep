targetScope = 'subscription'

import {
  existingMonitoringType
  hostingType
  identityType
  modelDeploymentType
  monitoringModeType
  networkModeType
  privateNetworkType
  resourceGroupNamesType
  resourceNamesType
  skusType
} from 'types.bicep'

@description('Short application name used in resource group and resource names.')
@minLength(2)
@maxLength(20)
param appName string

@description('Environment name such as dev, test, or prod.')
@minLength(2)
@maxLength(16)
param environmentName string

@description('Primary Azure region for application resources.')
@metadata({
  azd: {
    type: 'location'
  }
})
param location string

@description('public creates no private endpoints. private integrates with existing PBMM or ALZ networking.')
param networkMode networkModeType = 'public'

@description('none disables monitoring, new deploys application-owned monitoring, existing links to an existing platform.')
param monitoringMode monitoringModeType = 'new'

@description('Existing network resource IDs. Required only in private mode.')
param privateNetwork privateNetworkType = {}

@description('Existing monitoring values. Required only when monitoringMode is existing.')
param existingMonitoring existingMonitoringType = {}

@description('Optional resource group name overrides.')
param resourceGroupNames resourceGroupNamesType = {}

@description('Optional per-resource name overrides.')
param resourceNames resourceNamesType = {}

@description('Optional SKU and scale overrides.')
param skus skusType = {}

@description('Model deployments created on the Foundry account. Deployed one at a time.')
param modelDeployments modelDeploymentType[] = [
  {
    name: 'chat'
    model: 'gpt-4.1-mini'
    version: '2025-04-14'
    skuName: 'GlobalStandard'
    capacity: 10
  }
]

@description('Model deployment used by the sample API. Defaults to the first model deployment.')
param chatDeploymentName string = ''

@description('Tenant, developer principal, and App Service authentication settings.')
param identity identityType = {}

@description('Optional App Service Environment, CORS, and IP allow-list settings.')
param hosting hostingType = {}

@description('Token audience used by the Logic App when App Service authentication is disabled.')
param backendApiAudience string = 'api://logic-app-ai-accelerator'

@description('Container image for the web app. azd sets this after the first deployment so provisioning does not reset it.')
param webContainerImage string = ''

@description('Tags applied to deployed resources.')
param tags object = {}

func valueOrDefault(value string?, fallback string) string => empty(value ?? '') ? fallback : value!

var privateMode = networkMode == 'private'

// Naming
var normalizedAppName = toLower(replace(appName, '-', ''))
var normalizedEnvironmentName = toLower(replace(environmentName, '-', ''))
var resourceToken = '${take('${normalizedAppName}${normalizedEnvironmentName}', 8)}${uniqueString(subscription().id, appName, environmentName, location)}'
var applicationResourceGroupName = valueOrDefault(resourceGroupNames.?application, 'rg-${appName}-${environmentName}')
var aiResourceGroupName = valueOrDefault(resourceGroupNames.?ai, 'rg-${appName}-ai-${environmentName}')
var operationsResourceGroupName = valueOrDefault(resourceGroupNames.?operations, 'rg-${appName}-ops-${environmentName}')
var names = {
  storageAccount: valueOrDefault(resourceNames.?storageAccount, 'sta${resourceToken}')
  logicStorageAccount: valueOrDefault(resourceNames.?logicStorageAccount, 'stl${resourceToken}')
  cosmosAccount: valueOrDefault(resourceNames.?cosmosAccount, 'cosmos-${resourceToken}')
  containerRegistry: valueOrDefault(resourceNames.?containerRegistry, 'cr${resourceToken}')
  webAppPlan: valueOrDefault(resourceNames.?webAppPlan, 'asp-web-${resourceToken}')
  webApp: valueOrDefault(resourceNames.?webApp, 'app-${resourceToken}')
  webIdentity: valueOrDefault(resourceNames.?webIdentity, 'id-web-${resourceToken}')
  logicAppPlan: valueOrDefault(resourceNames.?logicAppPlan, 'asp-logic-${resourceToken}')
  logicApp: valueOrDefault(resourceNames.?logicApp, 'logic-${resourceToken}')
  logicIdentity: valueOrDefault(resourceNames.?logicIdentity, 'id-logic-${resourceToken}')
  foundryAccount: valueOrDefault(resourceNames.?foundryAccount, 'aif-${resourceToken}')
  foundryProject: valueOrDefault(resourceNames.?foundryProject, 'proj-${normalizedAppName}')
  documentIntelligence: valueOrDefault(resourceNames.?documentIntelligence, 'di-${resourceToken}')
  search: valueOrDefault(resourceNames.?search, 'srch-${resourceToken}')
  logAnalytics: valueOrDefault(resourceNames.?logAnalytics, 'log-${resourceToken}')
  applicationInsights: valueOrDefault(resourceNames.?applicationInsights, 'appi-${resourceToken}')
  monitorPrivateLinkScope: valueOrDefault(resourceNames.?monitorPrivateLinkScope, 'ampls-${resourceToken}')
}
var commonTags = union(tags, {
  Application: appName
  Environment: environmentName
  ManagedBy: 'Bicep'
  Repository: 'logic-app-ai-accelerator'
  'azd-env-name': environmentName
})

// Hosting
var webAseId = hosting.?webAppServiceEnvironmentId ?? ''
var logicAseId = hosting.?logicAppServiceEnvironmentId ?? ''
var corsAllowedOrigins = hosting.?corsAllowedOrigins ?? []
var allowedIpRanges = !privateMode
  ? hosting.?allowedIpRanges ?? []
  : empty(hosting.?allowedIpRanges ?? [])
    ? []
    : fail('hosting.allowedIpRanges applies only to public mode. Private mode disables public access.')

// SKUs
var webAppPlanSku = skus.?webAppPlan ?? {
  name: 'P1v3'
  tier: 'PremiumV3'
  capacity: 1
}
var logicAppPlanSku = skus.?logicAppPlan ?? {
  name: 'WS1'
  tier: 'WorkflowStandard'
  capacity: 1
}
var containerRegistrySku = skus.?containerRegistry ?? 'Premium'
var resolvedSkus = {
  webAppPlan: empty(webAseId) || startsWith(toUpper(webAppPlanSku.name), 'I')
    ? webAppPlanSku
    : fail('skus.webAppPlan must be an Isolated v2 SKU such as I1v2 when hosting.webAppServiceEnvironmentId is set.')
  logicAppPlan: !empty(logicAseId)
    ? startsWith(toUpper(logicAppPlanSku.name), 'I')
      ? logicAppPlanSku
      : fail('skus.logicAppPlan must be an Isolated v2 SKU such as I1v2 when hosting.logicAppServiceEnvironmentId is set.')
    : contains(['WS1', 'WS2', 'WS3'], toUpper(logicAppPlanSku.name))
      ? logicAppPlanSku
      : fail('skus.logicAppPlan must be WS1, WS2, or WS3.')
  containerRegistry: !privateMode || containerRegistrySku == 'Premium'
    ? containerRegistrySku
    : fail('skus.containerRegistry must be Premium in private mode because private endpoints require Premium.')
  search: skus.?search ?? {
    name: 'standard'
  }
  aiServices: skus.?aiServices ?? 'S0'
  documentIntelligence: skus.?documentIntelligence ?? 'S0'
  cosmos: skus.?cosmos ?? {
    mode: 'serverless'
  }
  storage: skus.?storage ?? 'Standard_LRS'
  logAnalyticsRetentionInDays: skus.?logAnalyticsRetentionInDays ?? 30
}

// Models
var modelDeploymentNames = map(modelDeployments, deployment => deployment.name)
var resolvedChatDeploymentName = empty(modelDeployments)
  ? fail('At least one model deployment is required.')
  : empty(chatDeploymentName)
    ? modelDeployments[0].name
    : contains(modelDeploymentNames, chatDeploymentName)
      ? chatDeploymentName
      : fail('chatDeploymentName must match a name in modelDeployments.')

// Identity
var tenantId = valueOrDefault(identity.?tenantId, tenant().tenantId)
var authTenantId = valueOrDefault(identity.?authTenantId, tenantId)
var principalId = identity.?principalId ?? ''
var principalType = identity.?principalType ?? 'User'
var enableAppServiceAuth = identity.?enableAppServiceAuth ?? false
var appServiceAuthClientId = !enableAppServiceAuth
  ? ''
  : !empty(identity.?appServiceAuthClientId ?? '')
    ? identity.appServiceAuthClientId!
    : fail('identity.appServiceAuthClientId is required when identity.enableAppServiceAuth is true. The azd preprovision hook creates it.')
var resolvedBackendApiAudience = enableAppServiceAuth ? 'api://${appServiceAuthClientId}' : backendApiAudience

// Private networking
var privateEndpointSubnetId = !privateMode
  ? ''
  : !empty(privateNetwork.?privateEndpointSubnetId ?? '')
    ? privateNetwork.privateEndpointSubnetId!
    : fail('privateNetwork.privateEndpointSubnetId is required in private mode.')
var webIntegrationSubnetId = !privateMode || !empty(webAseId)
  ? ''
  : !empty(privateNetwork.?webIntegrationSubnetId ?? '')
    ? privateNetwork.webIntegrationSubnetId!
    : fail('privateNetwork.webIntegrationSubnetId is required in private mode unless the web app uses an App Service Environment.')
var logicIntegrationSubnetId = !privateMode || !empty(logicAseId)
  ? ''
  : !empty(privateNetwork.?logicIntegrationSubnetId ?? '')
    ? privateNetwork.logicIntegrationSubnetId!
    : fail('privateNetwork.logicIntegrationSubnetId is required in private mode unless the Logic App uses an App Service Environment.')

var agentSubnetId = privateMode ? (privateNetwork.?agentSubnetId ?? '') : ''

var subnetsAreDistinct = (empty(webIntegrationSubnetId) || toLower(webIntegrationSubnetId) != toLower(privateEndpointSubnetId)) && (empty(logicIntegrationSubnetId) || toLower(logicIntegrationSubnetId) != toLower(privateEndpointSubnetId)) && (empty(webIntegrationSubnetId) || toLower(webIntegrationSubnetId) != toLower(logicIntegrationSubnetId)) && (empty(agentSubnetId) || (toLower(agentSubnetId) != toLower(privateEndpointSubnetId) && toLower(agentSubnetId) != toLower(webIntegrationSubnetId) && toLower(agentSubnetId) != toLower(logicIntegrationSubnetId)))
var distinctPrivateSubnets = !privateMode || subnetsAreDistinct
  ? true
  : fail('Private endpoint, web integration, Logic App integration, and agent subnets must be separate.')

var suppliedDnsZoneIds = privateNetwork.?privateDnsZoneIds ?? {}
var privateDnsZoneIds = !privateMode
  ? {}
  : {
      blob: !empty(suppliedDnsZoneIds.?blob ?? '') ? suppliedDnsZoneIds.blob! : fail('Private DNS zone blob is required.')
      file: !empty(suppliedDnsZoneIds.?file ?? '') ? suppliedDnsZoneIds.file! : fail('Private DNS zone file is required.')
      queue: !empty(suppliedDnsZoneIds.?queue ?? '') ? suppliedDnsZoneIds.queue! : fail('Private DNS zone queue is required.')
      table: !empty(suppliedDnsZoneIds.?table ?? '') ? suppliedDnsZoneIds.table! : fail('Private DNS zone table is required.')
      cosmosSql: !empty(suppliedDnsZoneIds.?cosmosSql ?? '') ? suppliedDnsZoneIds.cosmosSql! : fail('Private DNS zone cosmosSql is required.')
      acr: !empty(suppliedDnsZoneIds.?acr ?? '') ? suppliedDnsZoneIds.acr! : fail('Private DNS zone acr is required.')
      sites: !empty(suppliedDnsZoneIds.?sites ?? '') ? suppliedDnsZoneIds.sites! : fail('Private DNS zone sites is required.')
      cognitiveServices: !empty(suppliedDnsZoneIds.?cognitiveServices ?? '') ? suppliedDnsZoneIds.cognitiveServices! : fail('Private DNS zone cognitiveServices is required.')
      openAi: !empty(suppliedDnsZoneIds.?openAi ?? '') ? suppliedDnsZoneIds.openAi! : fail('Private DNS zone openAi is required.')
      aiServices: !empty(suppliedDnsZoneIds.?aiServices ?? '') ? suppliedDnsZoneIds.aiServices! : fail('Private DNS zone aiServices is required.')
      search: !empty(suppliedDnsZoneIds.?search ?? '') ? suppliedDnsZoneIds.search! : fail('Private DNS zone search is required.')
      monitor: monitoringMode != 'new'
        ? ''
        : !empty(suppliedDnsZoneIds.?monitor ?? '') ? suppliedDnsZoneIds.monitor! : fail('Private DNS zone monitor is required for new private monitoring.')
      oms: monitoringMode != 'new'
        ? ''
        : !empty(suppliedDnsZoneIds.?oms ?? '') ? suppliedDnsZoneIds.oms! : fail('Private DNS zone oms is required for new private monitoring.')
      ods: monitoringMode != 'new'
        ? ''
        : !empty(suppliedDnsZoneIds.?ods ?? '') ? suppliedDnsZoneIds.ods! : fail('Private DNS zone ods is required for new private monitoring.')
      agentsvc: monitoringMode != 'new'
        ? ''
        : !empty(suppliedDnsZoneIds.?agentsvc ?? '') ? suppliedDnsZoneIds.agentsvc! : fail('Private DNS zone agentsvc is required for new private monitoring.')
    }

// Monitoring
var existingApplicationInsightsConnectionString = monitoringMode != 'existing'
  ? ''
  : !empty(existingMonitoring.?applicationInsightsConnectionString ?? '')
    ? existingMonitoring.applicationInsightsConnectionString!
    : fail('existingMonitoring.applicationInsightsConnectionString is required in existing mode.')
var existingLogAnalyticsWorkspaceId = monitoringMode != 'existing'
  ? ''
  : !empty(existingMonitoring.?logAnalyticsWorkspaceId ?? '')
    ? existingMonitoring.logAnalyticsWorkspaceId!
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
    tags: commonTags
    networkMode: networkMode
    names: names
    storageSku: resolvedSkus.storage
    cosmosSku: resolvedSkus.cosmos
    containerRegistrySku: resolvedSkus.containerRegistry
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneIds: privateDnsZoneIds
  }
}

module monitoring './modules/monitoring/stack.bicep' = if (monitoringMode == 'new') {
  name: 'monitoring'
  scope: operationsResourceGroup
  params: {
    location: location
    tags: commonTags
    networkMode: networkMode
    names: names
    retentionInDays: resolvedSkus.logAnalyticsRetentionInDays
    privateEndpointSubnetId: privateEndpointSubnetId
    privateDnsZoneIds: privateDnsZoneIds
  }
}

module ai './modules/ai/stack.bicep' = {
  name: 'ai-stack'
  scope: aiResourceGroup
  params: {
    location: location
    tags: commonTags
    networkMode: networkMode
    names: names
    aiServicesSku: resolvedSkus.aiServices
    documentIntelligenceSku: resolvedSkus.documentIntelligence
    searchSku: resolvedSkus.search
    modelDeployments: modelDeployments
    chatDeploymentName: resolvedChatDeploymentName
    privateEndpointSubnetId: privateEndpointSubnetId
    agentSubnetId: agentSubnetId
    privateDnsZoneIds: privateDnsZoneIds
    storageName: data.outputs.storageName
    storageId: data.outputs.storageId
    storageBlobEndpoint: data.outputs.storageBlobEndpoint
    cosmosName: data.outputs.cosmosName
    cosmosId: data.outputs.cosmosId
    cosmosEndpoint: data.outputs.cosmosEndpoint
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
    tags: commonTags
    networkMode: networkMode
    names: names
    webAppPlanSku: resolvedSkus.webAppPlan
    logicAppPlanSku: resolvedSkus.logicAppPlan
    webAppServiceEnvironmentId: webAseId
    logicAppServiceEnvironmentId: logicAseId
    corsAllowedOrigins: corsAllowedOrigins
    allowedIpRanges: allowedIpRanges
    privateEndpointSubnetId: privateEndpointSubnetId
    webIntegrationSubnetId: distinctPrivateSubnets ? webIntegrationSubnetId : ''
    logicIntegrationSubnetId: logicIntegrationSubnetId
    privateDnsZoneIds: privateDnsZoneIds
    storageBlobEndpoint: data.outputs.storageBlobEndpoint
    logicStorageId: data.outputs.logicStorageId
    cosmosEndpoint: data.outputs.cosmosEndpoint
    registryLoginServer: data.outputs.registryLoginServer
    webContainerImage: webContainerImage
    foundryOpenAiEndpoint: ai.outputs.foundryOpenAiEndpoint
    documentIntelligenceEndpoint: ai.outputs.documentIntelligenceEndpoint
    searchEndpoint: ai.outputs.searchEndpoint
    modelDeploymentName: resolvedChatDeploymentName
    monitoringMode: monitoringMode
    applicationInsightsConnectionString: applicationInsightsConnectionString
    logAnalyticsWorkspaceId: logAnalyticsWorkspaceId
    tenantId: tenantId
    authTenantId: authTenantId
    enableAppServiceAuth: enableAppServiceAuth
    appServiceAuthClientId: appServiceAuthClientId
    backendApiAudience: resolvedBackendApiAudience
  }
}

// Workload identity roles
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

module projectCapabilityHost './modules/ai/project-capability-host.bicep' = {
  name: 'foundry-project-capability-host'
  scope: aiResourceGroup
  params: {
    foundryName: ai.outputs.foundryName
    projectName: ai.outputs.foundryProjectName
    storageConnectionName: data.outputs.storageName
    threadStorageConnectionName: data.outputs.cosmosName
    vectorStoreConnectionName: ai.outputs.searchName
  }
  dependsOn: [
    foundryProjectAppRoles
    foundryProjectAiRoles
  ]
}

module foundryProjectPostRoles './modules/ai/project-post-capability-host-roles.bicep' = {
  name: 'foundry-project-post-capability-host-roles'
  scope: applicationResourceGroup
  params: {
    cosmosAccountName: data.outputs.cosmosName
    storageAccountName: data.outputs.storageName
    projectPrincipalId: ai.outputs.foundryProjectPrincipalId
    projectWorkspaceId: ai.outputs.foundryProjectWorkspaceId
  }
  dependsOn: [
    projectCapabilityHost
  ]
}

module webCosmosDataRole './modules/shared/cosmos-data-role.bicep' = {
  name: 'web-cosmos-data-role'
  scope: applicationResourceGroup
  params: {
    accountName: data.outputs.cosmosName
    principalId: compute.outputs.webPrincipalId
  }
}

// Developer or deployment principal roles
module developerAppRoles './modules/shared/role-assignment.bicep' = [
  for role in [
    {
      id: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
      name: 'storage-blob-contributor'
    }
    {
      id: '8311e382-0749-4cb8-b61a-304f252e45ec'
      name: 'acr-push'
    }
  ]: if (!empty(principalId)) {
    name: 'developer-${role.name}'
    scope: applicationResourceGroup
    params: {
      principalId: principalId
      principalType: principalType
      roleDefinitionId: role.id
      seed: 'developer-${role.name}'
    }
  }
]

module developerAiRoles './modules/shared/role-assignment.bicep' = [
  for role in [
    {
      id: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
      name: 'azure-ai-user'
    }
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
    {
      id: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
      name: 'search-service-contributor'
    }
  ]: if (!empty(principalId)) {
    name: 'developer-${role.name}'
    scope: aiResourceGroup
    params: {
      principalId: principalId
      principalType: principalType
      roleDefinitionId: role.id
      seed: 'developer-${role.name}'
    }
  }
]

module developerCosmosDataRole './modules/shared/cosmos-data-role.bicep' = if (!empty(principalId)) {
  name: 'developer-cosmos-data-role'
  scope: applicationResourceGroup
  params: {
    accountName: data.outputs.cosmosName
    principalId: principalId
  }
}

// Outputs use azd naming so `azd provision` stores them in the environment.
output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenantId
output AZURE_AUTH_TENANT_ID string = authTenantId
output AZURE_RESOURCE_GROUP string = applicationResourceGroup.name
output AZURE_APPLICATION_RESOURCE_GROUP string = applicationResourceGroup.name
output AZURE_AI_RESOURCE_GROUP string = aiResourceGroup.name
output AZURE_OPERATIONS_RESOURCE_GROUP string = monitoringMode == 'new' ? operationsResourceGroup.name : ''
output AZURE_CONTAINER_REGISTRY_NAME string = data.outputs.registryName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = data.outputs.registryLoginServer
output AZURE_STORAGE_ENDPOINT string = data.outputs.storageBlobEndpoint
output AZURE_COSMOS_ENDPOINT string = data.outputs.cosmosEndpoint
output WEB_APP_NAME string = compute.outputs.webName
output WEB_APP_URI string = compute.outputs.webUri
output WEB_IDENTITY_PRINCIPAL_ID string = compute.outputs.webIdentityPrincipalId
output WEB_IDENTITY_CLIENT_ID string = compute.outputs.webIdentityClientId
output LOGIC_APP_NAME string = compute.outputs.logicName
output AZURE_FOUNDRY_ACCOUNT_NAME string = ai.outputs.foundryName
output AZURE_FOUNDRY_PROJECT_ID string = ai.outputs.foundryProjectId
output AZURE_FOUNDRY_PROJECT_ENDPOINT string = ai.outputs.foundryProjectEndpoint
output AZURE_FOUNDRY_OPENAI_ENDPOINT string = ai.outputs.foundryOpenAiEndpoint
output AZURE_MODEL_DEPLOYMENT string = resolvedChatDeploymentName
output AZURE_MODEL_DEPLOYMENTS array = modelDeploymentNames
output AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT string = ai.outputs.documentIntelligenceEndpoint
output AZURE_SEARCH_ENDPOINT string = ai.outputs.searchEndpoint
output AZURE_APP_SERVICE_AUTH_ENABLED bool = enableAppServiceAuth
