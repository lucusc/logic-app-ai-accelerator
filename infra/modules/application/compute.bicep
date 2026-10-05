param location string
param resourceToken string
param tags object
param networkMode string
param privateEndpointSubnetId string = ''
param webIntegrationSubnetId string = ''
param logicIntegrationSubnetId string = ''
param privateDnsZoneIds object = {}
param storageId string
param storageName string
param storageBlobEndpoint string
param logicStorageId string
param logicStorageName string
param cosmosId string
param cosmosName string
param cosmosEndpoint string
param registryId string
param registryLoginServer string
param foundryId string
param foundryOpenAiEndpoint string
param documentIntelligenceId string
param documentIntelligenceEndpoint string
param searchId string
param searchEndpoint string
param modelDeploymentName string
param monitoringMode string
param applicationInsightsConnectionString string = ''
param logAnalyticsWorkspaceId string = ''
param backendApiAudience string = 'api://logic-app-ai-accelerator'

var privateMode = networkMode == 'private'
var webName = 'app-${resourceToken}'
var logicName = 'logic-${resourceToken}'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource logicStorage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: logicStorageName
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosName
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: last(split(registryId, '/'))
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: last(split(foundryId, '/'))
  scope: resourceGroup(split(foundryId, '/')[4])
}

resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: last(split(documentIntelligenceId, '/'))
  scope: resourceGroup(split(documentIntelligenceId, '/')[4])
}

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: last(split(searchId, '/'))
  scope: resourceGroup(split(searchId, '/')[4])
}

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

resource webAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, web.identity.principalId, 'acr-pull')
  scope: registry
  properties: {
    principalId: web.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '7f951dda-4ed3-4680-a7ca-43fe172d538d'
    )
  }
}

resource webStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, web.identity.principalId, 'storage-blob-data-contributor')
  scope: storage
  properties: {
    principalId: web.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
  }
}

resource webFoundryUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(foundry.id, web.identity.principalId, 'cognitive-services-openai-user')
  scope: foundry
  properties: {
    principalId: web.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
    )
  }
}

resource webDocumentIntelligenceUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(documentIntelligence.id, web.identity.principalId, 'cognitive-services-user')
  scope: documentIntelligence
  properties: {
    principalId: web.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'a97b65f3-24c7-4388-baec-2e87135dc908'
    )
  }
}

resource webSearchContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, web.identity.principalId, 'search-index-data-contributor')
  scope: search
  properties: {
    principalId: web.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
    )
  }
}

resource webCosmosDataContributor 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-11-15' = {
  name: guid(cosmos.id, web.identity.principalId, 'cosmos-data-contributor')
  parent: cosmos
  properties: {
    principalId: web.identity.principalId
    roleDefinitionId: '${cosmos.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmos.id
  }
}

var logicStorageRoles = [
  'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  '69566ab7-960f-475b-8e7c-b3118f30c6bd'
]

resource logicStorageRoleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleId in logicStorageRoles: {
    name: guid(logicStorage.id, logicIdentity.properties.principalId, roleId)
    scope: logicStorage
    properties: {
      principalId: logicIdentity.properties.principalId
      principalType: 'ServicePrincipal'
      roleDefinitionId: subscriptionResourceId(
        'Microsoft.Authorization/roleDefinitions',
        roleId
      )
    }
  }
]

resource logicApplicationStorageContributor 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, logicIdentity.properties.principalId, 'storage-blob-data-contributor')
  scope: storage
  properties: {
    principalId: logicIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
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

