param location string
param tags object
@description('Resolved resource names from main.bicep.')
param names object
param networkMode string
param privateEndpointSubnetId string = ''
param privateDnsZoneIds object = {}
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
var foundryName = names.foundryAccount
var searchName = names.search

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
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
  }
}

// Deployments on one account must be created sequentially.
@batchSize(1)
resource modelDeploymentResources 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = [
  for deployment in modelDeployments: {
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

resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: names.documentIntelligence
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
    customSubDomainName: names.documentIntelligence
    disableLocalAuth: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: privateMode ? 'Deny' : 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
  }
}

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' = {
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
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
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

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
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
        ResourceId: search.id
        location: location
      }
    }
  }
}

resource accountCapabilityHost 'Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview' = {
  parent: foundry
  name: 'agents'
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
  }
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: 'agents'
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: [
      storageName
    ]
    threadStorageConnections: [
      cosmosName
    ]
    vectorStoreConnections: [
      searchName
    ]
  }
  dependsOn: [
    accountCapabilityHost
    modelDeploymentResources
  ]
}

module foundryPe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'foundry-private-endpoint'
  params: {
    name: 'pe-${foundry.name}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: foundry.id
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
    name: 'pe-${documentIntelligence.name}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: documentIntelligence.id
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
    name: 'pe-${search.name}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: search.id
    groupIds: [
      'searchService'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.search
    ]
    tags: tags
  }
}

output foundryId string = foundry.id
output foundryName string = foundry.name
output foundryEndpoint string = foundry.properties.endpoint
output foundryOpenAiEndpoint string = 'https://${foundry.name}.openai.azure.com'
output foundryProjectId string = project.id
output foundryProjectEndpoint string = 'https://${foundry.properties.customSubDomainName}.services.ai.azure.com/api/projects/${project.name}'
output foundryProjectPrincipalId string = project.identity.principalId
output documentIntelligenceId string = documentIntelligence.id
output documentIntelligenceEndpoint string = documentIntelligence.properties.endpoint
output searchId string = search.id
output searchEndpoint string = 'https://${search.name}.search.windows.net'
output searchName string = search.name
output chatDeploymentName string = modelDeploymentResources[indexOf(map(modelDeployments, d => d.name), chatDeploymentName)].name
