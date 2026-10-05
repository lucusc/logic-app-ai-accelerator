param location string
param tags object
param networkMode string
@description('Resolved resource names from main.bicep.')
param names object
param privateEndpointSubnetId string = ''
param privateDnsZoneIds object = {}
param storageSku string = 'Standard_LRS'
@description('Cosmos DB capacity mode: { mode: serverless | provisioned, throughput?: int }.')
param cosmosSku object = {
  mode: 'serverless'
}
param containerRegistrySku string = 'Premium'

var privateMode = networkMode == 'private'
var cosmosServerless = cosmosSku.mode == 'serverless'

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: names.storageAccount
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: storageSku
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: privateMode ? 'Deny' : 'Allow'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    deleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource documentsContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'documents'
  properties: {
    publicAccess: 'None'
  }
}

resource logicStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: names.logicStorageAccount
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: storageSku
  }
  properties: {
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: privateMode ? 'Deny' : 'Allow'
    }
  }
}

resource cosmos 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: names.cosmosAccount
  location: location
  tags: tags
  kind: 'GlobalDocumentDB'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    capabilities: cosmosServerless
      ? [
          {
            name: 'EnableServerless'
          }
        ]
      : []
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    databaseAccountOfferType: 'Standard'
    disableKeyBasedMetadataWriteAccess: true
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
    virtualNetworkRules: []
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-11-15' = {
  parent: cosmos
  name: 'accelerator'
  properties: {
    resource: {
      id: 'accelerator'
    }
    options: cosmosServerless
      ? {}
      : {
          throughput: cosmosSku.?throughput ?? 400
        }
  }
}

resource jobsContainer 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-11-15' = {
  parent: database
  name: 'jobs'
  properties: {
    resource: {
      id: 'jobs'
      partitionKey: {
        kind: 'Hash'
        paths: [
          '/id'
        ]
        version: 2
      }
    }
  }
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: names.containerRegistry
  location: location
  tags: tags
  sku: {
    name: containerRegistrySku
  }
  properties: {
    adminUserEnabled: false
    dataEndpointEnabled: false
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
    networkRuleBypassOptions: 'AzureServices'
    policies: containerRegistrySku != 'Premium' ? {} : {
      exportPolicy: {
        status: privateMode ? 'disabled' : 'enabled'
      }
      quarantinePolicy: {
        status: 'disabled'
      }
      retentionPolicy: {
        days: 7
        status: 'enabled'
      }
      trustPolicy: {
        status: 'disabled'
        type: 'Notary'
      }
    }
  }
}

module storageBlobPe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'storage-blob-private-endpoint'
  params: {
    name: 'pe-${storage.name}-blob'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: storage.id
    groupIds: [
      'blob'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.blob
    ]
    tags: tags
  }
}

module logicStorageEndpoints '../networking/private-endpoint.bicep' = [
  for endpoint in [
    {
      groupId: 'blob'
      zoneId: privateDnsZoneIds.?blob ?? ''
    }
    {
      groupId: 'file'
      zoneId: privateDnsZoneIds.?file ?? ''
    }
    {
      groupId: 'queue'
      zoneId: privateDnsZoneIds.?queue ?? ''
    }
    {
      groupId: 'table'
      zoneId: privateDnsZoneIds.?table ?? ''
    }
  ]: if (privateMode) {
    name: 'logic-storage-${endpoint.groupId}-private-endpoint'
    params: {
      name: 'pe-${logicStorage.name}-${endpoint.groupId}'
      location: location
      subnetId: privateEndpointSubnetId
      serviceId: logicStorage.id
      groupIds: [
        endpoint.groupId
      ]
      privateDnsZoneIds: [
        endpoint.zoneId
      ]
      tags: tags
    }
  }
]

module cosmosPe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'cosmos-private-endpoint'
  params: {
    name: 'pe-${cosmos.name}-sql'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: cosmos.id
    groupIds: [
      'Sql'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.cosmosSql
    ]
    tags: tags
  }
}

module registryPe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'registry-private-endpoint'
  params: {
    name: 'pe-${registry.name}-registry'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: registry.id
    groupIds: [
      'registry'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.acr
    ]
    tags: tags
  }
}

output storageId string = storage.id
output storageName string = storage.name
output storageBlobEndpoint string = storage.properties.primaryEndpoints.blob
output logicStorageId string = logicStorage.id
output logicStorageName string = logicStorage.name
output cosmosId string = cosmos.id
output cosmosName string = cosmos.name
output cosmosEndpoint string = cosmos.properties.documentEndpoint
output registryId string = registry.id
output registryName string = registry.name
output registryLoginServer string = registry.properties.loginServer
