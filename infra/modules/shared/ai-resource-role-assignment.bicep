// Grants a role on one existing AI resource. Deploy this module scoped to the
// resource's own subscription and resource group, so only that resource (not
// the whole resource group) receives the assignment.
@allowed([
  'cognitive'
  'search'
])
param kind string
param resourceName string
param principalId string
param roleDefinitionId string
param principalType string = 'ServicePrincipal'

resource cognitive 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (kind == 'cognitive') {
  name: resourceName
}

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' existing = if (kind == 'search') {
  name: resourceName
}

resource cognitiveAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (kind == 'cognitive') {
  scope: cognitive
  name: guid(cognitive.id, principalId, roleDefinitionId)
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}

resource searchAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (kind == 'search') {
  scope: search
  name: guid(search.id, principalId, roleDefinitionId)
  properties: {
    principalId: principalId
    principalType: principalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitionId)
  }
}
