// Test-only network that simulates what a PBMM/ALZ platform team provides:
// one VNet with separate subnets and the private DNS zones the accelerator
// consumes by resource ID. It is NOT part of the accelerator; deploy it once
// per test environment with scripts/test-network/deploy.sh.
targetScope = 'subscription'

param location string
param resourceGroupName string
param vnetName string = 'vnet-aiaccel-test'
param addressPrefix string = '10.20.0.0/16'

var dnsZoneNames = [
  'privatelink.blob.core.windows.net'
  'privatelink.file.core.windows.net'
  'privatelink.queue.core.windows.net'
  'privatelink.table.core.windows.net'
  'privatelink.documents.azure.com'
  'privatelink.azurecr.io'
  'privatelink.azurewebsites.net'
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.search.windows.net'
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
]

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
}

module network 'network.bicep' = {
  name: 'test-network'
  scope: rg
  params: {
    location: location
    vnetName: vnetName
    addressPrefix: addressPrefix
    dnsZoneNames: dnsZoneNames
  }
}

output resourceGroupId string = rg.id
output privateEndpointSubnetId string = network.outputs.privateEndpointSubnetId
output webIntegrationSubnetId string = network.outputs.webIntegrationSubnetId
output logicIntegrationSubnetId string = network.outputs.logicIntegrationSubnetId
output agentSubnetId string = network.outputs.agentSubnetId
output runnerSubnetId string = network.outputs.runnerSubnetId
