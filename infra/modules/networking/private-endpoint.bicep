param name string
param location string
param subnetId string
param serviceId string
param groupIds array
param privateDnsZoneIds array
param tags object = {}

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${name}-connection'
        properties: {
          privateLinkServiceId: serviceId
          groupIds: groupIds
        }
      }
    ]
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = if (!empty(privateDnsZoneIds)) {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for (zoneId, index) in privateDnsZoneIds: {
        name: 'zone-${index}'
        properties: {
          privateDnsZoneId: zoneId
        }
      }
    ]
  }
}

output id string = privateEndpoint.id

