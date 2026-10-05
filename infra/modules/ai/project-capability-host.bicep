// Deployed after the project identity's data roles exist; the capability host
// validates storage, Cosmos DB, and Search access when it is created.
param foundryName string
param projectName string
param storageConnectionName string
param threadStorageConnectionName string
param vectorStoreConnectionName string

resource foundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: foundryName

  resource project 'projects' existing = {
    name: projectName
  }
}

resource projectCapabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: foundry::project
  name: 'agents'
  properties: {
    #disable-next-line BCP037
    capabilityHostKind: 'Agents'
    storageConnections: [
      storageConnectionName
    ]
    threadStorageConnections: [
      threadStorageConnectionName
    ]
    vectorStoreConnections: [
      vectorStoreConnectionName
    ]
  }
}
