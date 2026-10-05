param location string
param resourceToken string
param tags object
param networkMode string
param privateEndpointSubnetId string = ''
param privateDnsZoneIds object = {}
param storageName string
param storageId string
param storageBlobEndpoint string
param cosmosName string
param cosmosId string
param cosmosEndpoint string
param modelName string = 'gpt-4.1-mini'
param modelVersion string = '2025-04-14'
param modelSkuName string = 'GlobalStandard'
param modelCapacity int = 10

var privateMode = networkMode == 'private'
var foundryName = 'aif-${resourceToken}'
var searchName = 'srch-${resourceToken}'

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: foundryName
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: 'S0'
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

resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: foundry
  name: modelName
  sku: {
    capacity: modelCapacity
    name: modelSkuName
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

resource documentIntelligence 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: 'di-${resourceToken}'
  location: location
  tags: tags
  kind: 'FormRecognizer'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: 'di-${resourceToken}'
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
    name: 'standard'
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
    partitionCount: 1
    publicNetworkAccess: privateMode ? 'disabled' : 'enabled'
    replicaCount: 1
    semanticSearch: 'free'
  }
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: foundry
  name: 'accelerator'
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
output modelDeploymentName string = modelDeployment.name
