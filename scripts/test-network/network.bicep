param location string
param vnetName string
param addressPrefix string
param dnsZoneNames array

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [addressPrefix]
    }
    subnets: [
      {
        name: 'snet-private-endpoints'
        properties: {
          addressPrefix: '10.20.0.0/24'
        }
      }
      {
        name: 'snet-web-integration'
        properties: {
          addressPrefix: '10.20.1.0/24'
          delegations: [
            {
              name: 'web'
              properties: { serviceName: 'Microsoft.Web/serverFarms' }
            }
          ]
        }
      }
      {
        name: 'snet-logic-integration'
        properties: {
          addressPrefix: '10.20.2.0/24'
          delegations: [
            {
              name: 'logic'
              properties: { serviceName: 'Microsoft.Web/serverFarms' }
            }
          ]
        }
      }
      {
        name: 'snet-foundry-agents'
        properties: {
          addressPrefix: '10.20.3.0/24'
          delegations: [
            {
              name: 'agents'
              properties: { serviceName: 'Microsoft.App/environments' }
            }
          ]
        }
      }
      {
        name: 'snet-runner'
        properties: {
          addressPrefix: '10.20.4.0/24'
        }
      }
    ]
  }
}

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in dnsZoneNames: {
    name: zone
    location: 'global'
  }
]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in dnsZoneNames: {
    parent: zones[i]
    name: 'link-${vnetName}'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

output privateEndpointSubnetId string = '${vnet.id}/subnets/snet-private-endpoints'
output webIntegrationSubnetId string = '${vnet.id}/subnets/snet-web-integration'
output logicIntegrationSubnetId string = '${vnet.id}/subnets/snet-logic-integration'
output agentSubnetId string = '${vnet.id}/subnets/snet-foundry-agents'
output runnerSubnetId string = '${vnet.id}/subnets/snet-runner'
