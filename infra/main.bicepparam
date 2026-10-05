// azd parameter file. azd compiles this with the current azd environment values,
// so every setting can be changed with `azd env set <NAME> <value>`.
using './main.bicep'

param appName = readEnvironmentVariable('AZURE_APP_NAME', 'aiaccel')
param environmentName = readEnvironmentVariable('AZURE_ENV_NAME', 'dev')
param location = readEnvironmentVariable('AZURE_LOCATION', 'canadacentral')
param networkMode = any(readEnvironmentVariable('AZURE_NETWORK_MODE', 'public'))
param monitoringMode = any(readEnvironmentVariable('AZURE_MONITORING_MODE', 'new'))

// Private networking. AZURE_PRIVATE_DNS_ZONES_RESOURCE_GROUP_ID builds standard Azure public cloud
// zone IDs from one resource group; AZURE_PRIVATE_DNS_ZONE_IDS (JSON) overrides individual zones
// (required for sovereign clouds, which use different zone names).
var dnsZonesResourceGroupId = readEnvironmentVariable('AZURE_PRIVATE_DNS_ZONES_RESOURCE_GROUP_ID', '')
var dnsZoneNames = {
  blob: 'privatelink.blob.core.windows.net'
  file: 'privatelink.file.core.windows.net'
  queue: 'privatelink.queue.core.windows.net'
  table: 'privatelink.table.core.windows.net'
  cosmosSql: 'privatelink.documents.azure.com'
  acr: 'privatelink.azurecr.io'
  sites: 'privatelink.azurewebsites.net'
  cognitiveServices: 'privatelink.cognitiveservices.azure.com'
  openAi: 'privatelink.openai.azure.com'
  aiServices: 'privatelink.services.ai.azure.com'
  search: 'privatelink.search.windows.net'
  monitor: 'privatelink.monitor.azure.com'
  oms: 'privatelink.oms.opinsights.azure.com'
  ods: 'privatelink.ods.opinsights.azure.com'
  agentsvc: 'privatelink.agentsvc.azure-automation.net'
}
var standardDnsZoneIds = empty(dnsZonesResourceGroupId)
  ? {}
  : toObject(
      items(dnsZoneNames),
      zone => zone.key,
      zone => '${dnsZonesResourceGroupId}/providers/Microsoft.Network/privateDnsZones/${zone.value}'
    )

param privateNetwork = {
  privateEndpointSubnetId: readEnvironmentVariable('AZURE_PRIVATE_ENDPOINT_SUBNET_ID', '')
  webIntegrationSubnetId: readEnvironmentVariable('AZURE_WEB_INTEGRATION_SUBNET_ID', '')
  logicIntegrationSubnetId: readEnvironmentVariable('AZURE_LOGIC_INTEGRATION_SUBNET_ID', '')
  agentSubnetId: readEnvironmentVariable('AZURE_AGENT_SUBNET_ID', '')
  privateDnsZoneIds: union(standardDnsZoneIds, json(readEnvironmentVariable('AZURE_PRIVATE_DNS_ZONE_IDS', '{}')))
}

param existingMonitoring = {
  applicationInsightsConnectionString: readEnvironmentVariable('AZURE_EXISTING_APPLICATION_INSIGHTS_CONNECTION_STRING', '')
  logAnalyticsWorkspaceId: readEnvironmentVariable('AZURE_EXISTING_LOG_ANALYTICS_WORKSPACE_ID', '')
  azureMonitorPrivateLinkScopeId: readEnvironmentVariable('AZURE_EXISTING_MONITOR_PRIVATE_LINK_SCOPE_ID', '')
}

param resourceGroupNames = {
  application: readEnvironmentVariable('AZURE_RG_APPLICATION_NAME', '')
  ai: readEnvironmentVariable('AZURE_RG_AI_NAME', '')
  operations: readEnvironmentVariable('AZURE_RG_OPERATIONS_NAME', '')
}

param resourceNames = {
  storageAccount: readEnvironmentVariable('AZURE_NAME_STORAGE_ACCOUNT', '')
  logicStorageAccount: readEnvironmentVariable('AZURE_NAME_LOGIC_STORAGE_ACCOUNT', '')
  cosmosAccount: readEnvironmentVariable('AZURE_NAME_COSMOS_ACCOUNT', '')
  containerRegistry: readEnvironmentVariable('AZURE_NAME_CONTAINER_REGISTRY', '')
  webAppPlan: readEnvironmentVariable('AZURE_NAME_WEB_APP_PLAN', '')
  webApp: readEnvironmentVariable('AZURE_NAME_WEB_APP', '')
  webIdentity: readEnvironmentVariable('AZURE_NAME_WEB_IDENTITY', '')
  logicAppPlan: readEnvironmentVariable('AZURE_NAME_LOGIC_APP_PLAN', '')
  logicApp: readEnvironmentVariable('AZURE_NAME_LOGIC_APP', '')
  logicIdentity: readEnvironmentVariable('AZURE_NAME_LOGIC_IDENTITY', '')
  foundryAccount: readEnvironmentVariable('AZURE_NAME_FOUNDRY_ACCOUNT', '')
  foundryProject: readEnvironmentVariable('AZURE_NAME_FOUNDRY_PROJECT', '')
  documentIntelligence: readEnvironmentVariable('AZURE_NAME_DOCUMENT_INTELLIGENCE', '')
  search: readEnvironmentVariable('AZURE_NAME_SEARCH', '')
  logAnalytics: readEnvironmentVariable('AZURE_NAME_LOG_ANALYTICS', '')
  applicationInsights: readEnvironmentVariable('AZURE_NAME_APPLICATION_INSIGHTS', '')
  monitorPrivateLinkScope: readEnvironmentVariable('AZURE_NAME_MONITOR_PRIVATE_LINK_SCOPE', '')
}

param skus = {
  webAppPlan: {
    name: readEnvironmentVariable('AZURE_WEB_APP_SKU', 'P1v3')
    tier: readEnvironmentVariable('AZURE_WEB_APP_SKU_TIER', '')
    capacity: int(readEnvironmentVariable('AZURE_WEB_APP_SKU_CAPACITY', '1'))
  }
  logicAppPlan: {
    name: readEnvironmentVariable('AZURE_LOGIC_APP_SKU', 'WS1')
    tier: readEnvironmentVariable('AZURE_LOGIC_APP_SKU_TIER', '')
    capacity: int(readEnvironmentVariable('AZURE_LOGIC_APP_SKU_CAPACITY', '1'))
  }
  containerRegistry: any(readEnvironmentVariable('AZURE_CONTAINER_REGISTRY_SKU', 'Premium'))
  search: {
    name: any(readEnvironmentVariable('AZURE_SEARCH_SKU', 'standard'))
    replicaCount: int(readEnvironmentVariable('AZURE_SEARCH_REPLICA_COUNT', '1'))
    partitionCount: int(readEnvironmentVariable('AZURE_SEARCH_PARTITION_COUNT', '1'))
    semanticSearch: any(readEnvironmentVariable('AZURE_SEARCH_SEMANTIC_SEARCH', 'free'))
  }
  aiServices: any(readEnvironmentVariable('AZURE_AI_SERVICES_SKU', 'S0'))
  documentIntelligence: any(readEnvironmentVariable('AZURE_DOCUMENT_INTELLIGENCE_SKU', 'S0'))
  cosmos: {
    mode: any(readEnvironmentVariable('AZURE_COSMOS_MODE', 'serverless'))
    throughput: int(readEnvironmentVariable('AZURE_COSMOS_THROUGHPUT', '400'))
  }
  storage: any(readEnvironmentVariable('AZURE_STORAGE_SKU', 'Standard_LRS'))
  logAnalyticsRetentionInDays: int(readEnvironmentVariable('AZURE_LOG_ANALYTICS_RETENTION_DAYS', '30'))
}

// Models. Set the chat and optional embedding variables, or replace the full list with
// AZURE_MODEL_DEPLOYMENTS as a JSON array of { name, model, version, skuName?, capacity? }.
var chatDeployment = {
  name: readEnvironmentVariable('AZURE_CHAT_DEPLOYMENT_NAME', 'chat')
  model: readEnvironmentVariable('AZURE_CHAT_MODEL_NAME', 'gpt-4.1-mini')
  version: readEnvironmentVariable('AZURE_CHAT_MODEL_VERSION', '2025-04-14')
  skuName: readEnvironmentVariable('AZURE_CHAT_DEPLOYMENT_SKU', 'GlobalStandard')
  capacity: int(readEnvironmentVariable('AZURE_CHAT_DEPLOYMENT_CAPACITY', '10'))
}
var embeddingModelName = readEnvironmentVariable('AZURE_EMBEDDING_MODEL_NAME', '')
var embeddingDeployments = empty(embeddingModelName)
  ? []
  : [
      {
        name: readEnvironmentVariable('AZURE_EMBEDDING_DEPLOYMENT_NAME', 'embedding')
        model: embeddingModelName
        version: readEnvironmentVariable('AZURE_EMBEDDING_MODEL_VERSION', '1')
        skuName: readEnvironmentVariable('AZURE_EMBEDDING_DEPLOYMENT_SKU', 'GlobalStandard')
        capacity: int(readEnvironmentVariable('AZURE_EMBEDDING_DEPLOYMENT_CAPACITY', '10'))
      }
    ]
var customModelDeployments = json(readEnvironmentVariable('AZURE_MODEL_DEPLOYMENTS', '[]'))

param modelDeployments = empty(customModelDeployments)
  ? concat([chatDeployment], embeddingDeployments)
  : customModelDeployments
param chatDeploymentName = empty(customModelDeployments) ? chatDeployment.name : readEnvironmentVariable('AZURE_CHAT_DEPLOYMENT_NAME', '')

param identity = {
  tenantId: readEnvironmentVariable('AZURE_TENANT_ID', '')
  authTenantId: readEnvironmentVariable('AZURE_AUTH_TENANT_ID', '')
  principalId: readEnvironmentVariable('AZURE_PRINCIPAL_ID', '')
  principalType: any(readEnvironmentVariable('AZURE_PRINCIPAL_TYPE', 'User'))
  enableAppServiceAuth: bool(readEnvironmentVariable('AZURE_USE_APP_SERVICE_AUTH', 'false'))
  appServiceAuthClientId: readEnvironmentVariable('AZURE_APP_SERVICE_AUTH_CLIENT_ID', '')
}

param hosting = {
  webAppServiceEnvironmentId: readEnvironmentVariable('AZURE_WEB_APP_SERVICE_ENVIRONMENT_ID', '')
  logicAppServiceEnvironmentId: readEnvironmentVariable('AZURE_LOGIC_APP_SERVICE_ENVIRONMENT_ID', '')
  corsAllowedOrigins: filter(map(split(readEnvironmentVariable('AZURE_CORS_ALLOWED_ORIGINS', ''), ','), item => trim(item)), item => !empty(item))
  allowedIpRanges: filter(map(split(readEnvironmentVariable('AZURE_ALLOWED_IP_RANGES', ''), ','), item => trim(item)), item => !empty(item))
}

param backendApiAudience = readEnvironmentVariable('AZURE_BACKEND_API_AUDIENCE', 'api://logic-app-ai-accelerator')
param webContainerImage = readEnvironmentVariable('SERVICE_WEB_IMAGE_NAME', '')
param tags = json(readEnvironmentVariable('AZURE_TAGS', '{}'))
