param location string
param tags object
@description('Resolved resource names from main.bicep.')
param names object
param networkMode string
@description('Per-service placement from main.bicep: { foundry|documentIntelligence|search: { isNew, subscriptionId, resourceGroup, name } }.')
param aiTargets object
param diagnosticsEnabled bool = false
param logAnalyticsWorkspaceId string = ''
param privateEndpointSubnetId string = ''
param privateDnsZoneIds object = {}
@description('Optional subnet delegated to Microsoft.App/environments. Enables Agent Service network injection.')
param agentSubnetId string = ''
param storageName string
param storageId string
param storageBlobEndpoint string
param cosmosName string
param cosmosId string
param cosmosEndpoint string
param aiServicesSku string = 'S0'
param documentIntelligenceSku string = 'S0'
@description('Search SKU: { name, replicaCount?, partitionCount?, semanticSearch? }.')
param searchSku object = {
  name: 'standard'
}
@description('Model deployments: [{ name, model, version, format?, skuName?, capacity?, versionUpgradeOption? }].')
param modelDeployments array
param chatDeploymentName string

var privateMode = networkMode == 'private'
var useAgentNetworkInjection = privateMode && foundryIsNew && !empty(agentSubnetId)
var foundryIsNew = aiTargets.foundry.isNew
var documentIntelligenceIsNew = aiTargets.documentIntelligence.isNew
var searchIsNew = aiTargets.search.isNew
var foundryName = aiTargets.foundry.name
var searchName = aiTargets.search.name
var foundryId = resourceId(aiTargets.foundry.subscriptionId, aiTargets.foundry.resourceGroup, 'Microsoft.CognitiveServices/accounts', foundryName)
var documentIntelligenceName = aiTargets.documentIntelligence.name
var documentIntelligenceId = resourceId(aiTargets.documentIntelligence.subscriptionId, aiTargets.documentIntelligence.resourceGroup, 'Microsoft.CognitiveServices/accounts', documentIntelligenceName)
var searchId = resourceId(aiTargets.search.subscriptionId, aiTargets.search.resourceGroup, 'Microsoft.Search/searchServices', searchName)

var diagnosticLogs = [
  {
    categoryGroup: 'allLogs'
    enabled: true
  }
]
var diagnosticMetrics = [
  {
    category: 'AllMetrics'
    enabled: true
  }
]

resource foundryExisting 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = if (!foundryIsNew) {
  name: foundryName
  scope: resourceGroup(aiTargets.foundry.subscriptionId, aiTargets.foundry.resourceGroup)
}

resource documentIntelligenceExisting 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (!documentIntelligenceIsNew) {
  name: documentIntelligenceName
  scope: resourceGroup(aiTargets.documentIntelligence.subscriptionId, aiTargets.documentIntelligence.resourceGroup)
}

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = if (foundryIsNew) {
  name: foundryName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: aiServicesSku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    allowProjectManagement: true
    customSubDomainName: foundryName
    disableLocalAuth: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: privateMode ? 'Deny' : 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
    networkInjections: useAgentNetworkInjection
      ? [
          {
            scenario: 'agent'
            subnetArmId: agentSubnetId
            useMicrosoftManagedNetwork: false
          }
        ]
      : null
  }
}

// Deployments on one account must be created sequentially.
@batchSize(1)
resource modelDeploymentResources 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = [
  for deployment in modelDeployments: if (foundryIsNew) {
    parent: foundry
    name: deployment.name
    sku: {
      capacity: deployment.?capacity ?? 10
      name: deployment.?skuName ?? 'GlobalStandard'
    }
    properties: {
      model: {
        format: deployment.?format ?? 'OpenAI'
        name: deployment.model
        version: deployment.version
      }
      versionUpgradeOption: deployment.?versionUpgradeOption ?? 'OnceNewDefaultVersionAvailable'
    }
  }
]

resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2024-10-01' = if (documentIntelligenceIsNew) {
  name: documentIntelligenceName
  location: location
  tags: tags
  kind: 'FormRecognizer'
  sku: {
    name: documentIntelligenceSku
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: documentIntelligenceName
    disableLocalAuth: true
    networkAcls: {
      defaultAction: privateMode ? 'Deny' : 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
  }
}

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = if (searchIsNew) {
  name: searchName
  location: location
  tags: tags
  sku: {
    name: searchSku.name
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    disableLocalAuth: true
    hostingMode: 'default'
    networkRuleSet: {
      bypass: 'None'
      ipRules: []
    }
    partitionCount: searchSku.?partitionCount ?? 1
    publicNetworkAccess: privateMode ? 'disabled' : 'enabled'
    replicaCount: searchSku.?replicaCount ?? 1
    semanticSearch: searchSku.?semanticSearch ?? 'free'
  }
}

// The project, its connections, and the capability hosts exist only with a new Foundry account.
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = if (foundryIsNew) {
  parent: foundry
  name: names.foundryProject
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: 'Logic App AI Accelerator project'
    displayName: 'Logic App AI Accelerator'
  }

  resource cosmosConnection 'connections@2025-04-01-preview' = {
    name: cosmosName
    properties: {
      authType: 'AAD'
      category: 'CosmosDB'
      target: cosmosEndpoint
      metadata: {
        ApiType: 'Azure'
        ResourceId: cosmosId
        location: location
      }
    }
  }

  resource storageConnection 'connections@2025-04-01-preview' = {
    name: storageName
    properties: {
      authType: 'AAD'
      category: 'AzureStorageAccount'
      target: storageBlobEndpoint
      metadata: {
        ApiType: 'Azure'
        ResourceId: storageId
        location: location
      }
    }
  }

  resource searchConnection 'connections@2025-04-01-preview' = {
    name: searchName
    properties: {
      authType: 'AAD'
      category: 'CognitiveSearch'
      target: 'https://${searchName}.search.windows.net'
      metadata: {
        ApiType: 'Azure'
        ResourceId: searchId
        location: location
      }
    }
  }
}

// With network injection the platform creates the account capability host itself.
resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview' = if (foundryIsNew && !useAgentNetworkInjection) {
  parent: foundry
  name: 'agents'
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
  }
}

module foundryPe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'foundry-private-endpoint'
  params: {
    name: 'pe-${foundryName}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: foundryId
    groupIds: [
      'account'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.cognitiveServices
      privateDnsZoneIds.openAi
      privateDnsZoneIds.aiServices
    ]
    tags: tags
  }
}

module documentIntelligencePe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'document-intelligence-private-endpoint'
  params: {
    name: 'pe-${documentIntelligenceName}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: documentIntelligenceId
    groupIds: [
      'account'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.cognitiveServices
    ]
    tags: tags
  }
}

module searchPe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'search-private-endpoint'
  params: {
    name: 'pe-${searchName}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: searchId
    groupIds: [
      'searchService'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.search
    ]
    tags: tags
  }
}

resource foundryDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (diagnosticsEnabled && foundryIsNew) {
  name: 'default'
  scope: foundry
  properties: {
    logs: diagnosticLogs
    metrics: diagnosticMetrics
    workspaceId: logAnalyticsWorkspaceId
  }
}

resource documentIntelligenceDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (diagnosticsEnabled && documentIntelligenceIsNew) {
  name: 'default'
  scope: documentIntelligence
  properties: {
    logs: diagnosticLogs
    metrics: diagnosticMetrics
    workspaceId: logAnalyticsWorkspaceId
  }
}

resource searchDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (diagnosticsEnabled && searchIsNew) {
  name: 'default'
  scope: search
  properties: {
    logs: diagnosticLogs
    metrics: diagnosticMetrics
    workspaceId: logAnalyticsWorkspaceId
  }
}

// internalId is returned by the API but missing from the Bicep types.
#disable-next-line BCP053
var projectInternalId = foundryIsNew ? project!.properties.internalId : ''
var foundryCustomSubDomain = foundryIsNew ? foundry!.properties.customSubDomainName : foundryExisting!.properties.customSubDomainName

output foundryId string = foundryId
output foundryName string = foundryName
output foundryEndpoint string = foundryIsNew ? foundry!.properties.endpoint : foundryExisting!.properties.endpoint
output foundryOpenAiEndpoint string = 'https://${foundryCustomSubDomain}.openai.azure.com'
output foundryProjectName string = foundryIsNew ? project!.name : ''
output foundryProjectWorkspaceId string = foundryIsNew ? '${substring(projectInternalId, 0, 8)}-${substring(projectInternalId, 8, 4)}-${substring(projectInternalId, 12, 4)}-${substring(projectInternalId, 16, 4)}-${substring(projectInternalId, 20, 12)}' : ''
output foundryProjectId string = foundryIsNew ? project!.id : ''
output foundryProjectEndpoint string = foundryIsNew ? 'https://${foundryCustomSubDomain}.services.ai.azure.com/api/projects/${project!.name}' : ''
output foundryProjectPrincipalId string = foundryIsNew ? project!.identity.principalId : ''
output documentIntelligenceId string = documentIntelligenceId
output documentIntelligenceEndpoint string = documentIntelligenceIsNew ? documentIntelligence!.properties.endpoint : documentIntelligenceExisting!.properties.endpoint
output searchId string = searchId
output searchEndpoint string = 'https://${searchName}.search.windows.net'
output searchName string = searchName
output chatDeploymentName string = chatDeploymentName
