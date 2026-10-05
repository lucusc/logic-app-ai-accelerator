// Shared parameter types for the accelerator. Every property is optional so
// callers only supply overrides; main.bicep resolves defaults.

@export()
type networkModeType = 'public' | 'private'

@export()
type monitoringModeType = 'none' | 'new' | 'existing'

@export()
type privateDnsZoneIdsType = {
  blob: string?
  file: string?
  queue: string?
  table: string?
  cosmosSql: string?
  acr: string?
  sites: string?
  cognitiveServices: string?
  openAi: string?
  aiServices: string?
  search: string?
  monitor: string?
  oms: string?
  ods: string?
  agentsvc: string?
}

@export()
@description('Existing PBMM/ALZ network resource IDs. Required only in private mode.')
type privateNetworkType = {
  privateEndpointSubnetId: string?
  webIntegrationSubnetId: string?
  logicIntegrationSubnetId: string?
  @description('Optional subnet delegated to Microsoft.App/environments for Foundry Agent Service network injection.')
  agentSubnetId: string?
  privateDnsZoneIds: privateDnsZoneIdsType?
}

@export()
@description('Existing monitoring resources. Required only when monitoringMode is existing.')
type existingMonitoringType = {
  applicationInsightsConnectionString: string?
  logAnalyticsWorkspaceId: string?
  @description('Accepted for documentation. The AMPLS owner manages scoped resources.')
  azureMonitorPrivateLinkScopeId: string?
}

@export()
type resourceGroupNamesType = {
  application: string?
  ai: string?
  operations: string?
}

@export()
type appServicePlanSkuType = {
  @description('App Service plan SKU name, for example B1, S1, P0v3, P1v3, I1v2, or WS1.')
  name: string
  tier: string?
  capacity: int?
}

@export()
type skusType = {
  webAppPlan: appServicePlanSkuType?
  @description('Use WS1, WS2, or WS3. Use an Isolated v2 SKU such as I1v2 with an App Service Environment.')
  logicAppPlan: appServicePlanSkuType?
  @description('Premium is required for private endpoints.')
  containerRegistry: ('Basic' | 'Standard' | 'Premium')?
  search: {
    name: ('basic' | 'standard' | 'standard2' | 'standard3' | 'storage_optimized_l1' | 'storage_optimized_l2')
    @minValue(1)
    @maxValue(12)
    replicaCount: int?
    @minValue(1)
    @maxValue(12)
    partitionCount: int?
    semanticSearch: ('disabled' | 'free' | 'standard')?
  }?
  aiServices: ('S0')?
  documentIntelligence: ('F0' | 'S0')?
  cosmos: {
    mode: ('serverless' | 'provisioned')
    @description('Shared database throughput in RU/s. Used only in provisioned mode.')
    @minValue(400)
    throughput: int?
  }?
  storage: ('Standard_LRS' | 'Standard_ZRS' | 'Standard_GRS' | 'Standard_RAGRS' | 'Standard_GZRS' | 'Standard_RAGZRS')?
  @minValue(30)
  @maxValue(730)
  logAnalyticsRetentionInDays: int?
}

@export()
@description('Optional per-resource name overrides. Defaults use standard abbreviations plus a unique token.')
type resourceNamesType = {
  storageAccount: string?
  logicStorageAccount: string?
  cosmosAccount: string?
  containerRegistry: string?
  webAppPlan: string?
  webApp: string?
  webIdentity: string?
  logicAppPlan: string?
  logicApp: string?
  logicIdentity: string?
  foundryAccount: string?
  foundryProject: string?
  documentIntelligence: string?
  search: string?
  logAnalytics: string?
  applicationInsights: string?
  monitorPrivateLinkScope: string?
}

@export()
type modelDeploymentType = {
  @description('Deployment name referenced by applications.')
  name: string
  @description('Model name, for example gpt-4.1-mini or text-embedding-3-small.')
  model: string
  version: string
  format: string?
  skuName: string?
  @minValue(1)
  capacity: int?
  versionUpgradeOption: ('NoAutoUpgrade' | 'OnceCurrentVersionExpired' | 'OnceNewDefaultVersionAvailable')?
}

@export()
type identityType = {
  @description('Tenant used for app settings. Defaults to the deployment tenant.')
  tenantId: string?
  @description('Tenant that issues sign-in tokens for App Service authentication. Defaults to tenantId.')
  authTenantId: string?
  @description('Object ID of the developer or deployment principal granted data-plane roles.')
  principalId: string?
  principalType: ('User' | 'Group' | 'ServicePrincipal')?
  @description('Enable App Service built-in authentication (Easy Auth) on the web app.')
  enableAppServiceAuth: bool?
  @description('Client ID of the Entra app registration used by App Service authentication.')
  appServiceAuthClientId: string?
}

@export()
type hostingType = {
  @description('Optional App Service Environment v3 resource ID for the web app plan.')
  webAppServiceEnvironmentId: string?
  @description('Optional App Service Environment v3 resource ID for the Logic App plan.')
  logicAppServiceEnvironmentId: string?
  @description('Additional CORS origins for the web app. Must start with https:// and have no trailing slash.')
  corsAllowedOrigins: string[]?
  @description('Inbound IPv4 CIDR ranges allowed to reach the web app and Logic App in public mode.')
  allowedIpRanges: string[]?
}
