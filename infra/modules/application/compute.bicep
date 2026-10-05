param location string
param resourceToken string
param tags object
param networkMode string
param privateEndpointSubnetId string = ''
param webIntegrationSubnetId string = ''
param logicIntegrationSubnetId string = ''
param privateDnsZoneIds object = {}
param storageBlobEndpoint string
param logicStorageId string
param cosmosEndpoint string
param registryLoginServer string
param foundryOpenAiEndpoint string
param documentIntelligenceEndpoint string
param searchEndpoint string
param modelDeploymentName string
param monitoringMode string
param applicationInsightsConnectionString string = ''
param logAnalyticsWorkspaceId string = ''
param backendApiAudience string = 'api://logic-app-ai-accelerator'

var privateMode = networkMode == 'private'
var webName = 'app-${resourceToken}'
var logicName = 'logic-${resourceToken}'

resource webPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-web-${resourceToken}'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: 'P1v3'
    capacity: 1
    tier: 'PremiumV3'
  }
  properties: {
    reserved: true
  }
}

resource web 'Microsoft.Web/sites@2024-04-01' = {
  name: webName
  location: location
  tags: union(tags, {
    'azd-service-name': 'web'
  })
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    clientAffinityEnabled: false
    httpsOnly: true
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
    serverFarmId: webPlan.id
    virtualNetworkSubnetId: privateMode ? webIntegrationSubnetId : null
    vnetImagePullEnabled: privateMode
    vnetRouteAllEnabled: privateMode
    siteConfig: {
      acrUseManagedIdentityCreds: true
      alwaysOn: true
      ftpsState: 'Disabled'
      http20Enabled: true
      linuxFxVersion: 'DOCKER|${registryLoginServer}/accelerator:latest'
      minTlsVersion: '1.2'
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          name: 'AZURE_STORAGE_ENDPOINT'
          value: storageBlobEndpoint
        }
        {
          name: 'AZURE_STORAGE_SUBMISSIONS_CONTAINER'
          value: 'documents'
        }
        {
          name: 'AZURE_COSMOS_ENDPOINT'
          value: cosmosEndpoint
        }
        {
          name: 'AZURE_COSMOS_DATABASE'
          value: 'accelerator'
        }
        {
          name: 'AZURE_COSMOS_CONTAINER'
          value: 'jobs'
        }
        {
          name: 'AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT'
          value: documentIntelligenceEndpoint
        }
        {
          name: 'AZURE_SEARCH_ENDPOINT'
          value: searchEndpoint
        }
        {
          name: 'AZURE_SEARCH_INDEX'
          value: 'documents'
        }
        {
          name: 'AZURE_FOUNDRY_OPENAI_ENDPOINT'
          value: foundryOpenAiEndpoint
        }
        {
          name: 'AZURE_MODEL_DEPLOYMENT'
          value: modelDeploymentName
        }
        {
          name: 'BACKEND_API_AUDIENCE'
          value: backendApiAudience
        }
        {
          name: 'WEBSITES_PORT'
          value: '8000'
        }
      ]
    }
  }
}

resource webFtpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: web
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource webScmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: web
  name: 'scm'
  properties: {
    allow: false
  }
}

resource logicIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-logic-${resourceToken}'
  location: location
  tags: tags
}

resource logicPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'plan-logic-${resourceToken}'
  location: location
  tags: tags
  kind: 'elastic'
  sku: {
    name: 'WS1'
    capacity: 1
    tier: 'WorkflowStandard'
  }
  properties: {
    reserved: false
  }
}

module logic 'br/public:avm/res/web/site:0.16.0' = {
  name: 'logic-app'
  params: {
    name: logicName
    location: location
    tags: union(tags, {
      'azd-service-name': 'logic'
    })
    kind: 'functionapp,workflowapp'
    serverFarmResourceId: logicPlan.id
    managedIdentities: {
      systemAssigned: true
      userAssignedResourceIds: [
        logicIdentity.id
      ]
    }
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
    virtualNetworkSubnetId: privateMode ? logicIntegrationSubnetId : null
    vnetContentShareEnabled: privateMode
    vnetImagePullEnabled: privateMode
    vnetRouteAllEnabled: privateMode
    storageAccountRequired: true
    configs: [
      {
        name: 'appsettings'
        retainCurrentAppSettings: true
        storageAccountResourceId: logicStorageId
        storageAccountUseIdentityAuthentication: true
        properties: {
          APP_KIND: 'workflowApp'
          APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsConnectionString
          FUNCTIONS_EXTENSION_VERSION: '~4'
          FUNCTIONS_WORKER_RUNTIME: 'dotnet'
          WEBSITE_NODE_DEFAULT_VERSION: '~20'
          WORKFLOWS_LOCATION_NAME: location
          WORKFLOWS_MANAGEMENT_BASE_URI: environment().resourceManager
          WORKFLOWS_RESOURCE_GROUP_NAME: resourceGroup().name
          WORKFLOWS_SUBSCRIPTION_ID: subscription().subscriptionId
          WORKFLOWS_TENANT_ID: tenant().tenantId
          AZURE_STORAGE_ENDPOINT: storageBlobEndpoint
          AZURE_STORAGE_SUBMISSIONS_CONTAINER: 'documents'
          BACKEND_API_URL: 'https://${web.properties.defaultHostName}'
          BACKEND_API_AUDIENCE: backendApiAudience
          AzureWebJobsStorage__credential: 'managedidentity'
          AzureWebJobsStorage__managedIdentityResourceId: logicIdentity.id
          WORKFLOWS_IDENTITY_RESOURCE_ID: logicIdentity.id
        }
      }
    ]
    siteConfig: {
      alwaysOn: true
      functionsRuntimeScaleMonitoringEnabled: true
      minTlsVersion: '1.2'
      use32BitWorkerProcess: false
    }
  }
}

resource webDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (monitoringMode != 'none') {
  name: 'default'
  scope: web
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspaceId
  }
}

module webPe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'web-private-endpoint'
  params: {
    name: 'pe-${web.name}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: web.id
    groupIds: [
      'sites'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.sites
    ]
    tags: tags
  }
}

module logicPe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'logic-private-endpoint'
  params: {
    name: 'pe-${logicName}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: logic.outputs.resourceId
    groupIds: [
      'sites'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.sites
    ]
    tags: tags
  }
}

output webName string = web.name
output webUri string = 'https://${web.properties.defaultHostName}'
output logicName string = logicName
output webPrincipalId string = web.identity.principalId
output logicPrincipalId string = logicIdentity.properties.principalId
