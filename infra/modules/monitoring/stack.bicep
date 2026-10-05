param location string
param tags object
@description('Resolved resource names from main.bicep.')
param names object
@minValue(30)
@maxValue(730)
param retentionInDays int = 30
param networkMode string
param privateEndpointSubnetId string = ''
param privateDnsZoneIds object = {}

var privateMode = networkMode == 'private'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: names.logAnalytics
  location: location
  tags: tags
  properties: {
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: privateMode ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: privateMode ? 'Disabled' : 'Enabled'
    retentionInDays: retentionInDays
    sku: {
      name: 'PerGB2018'
    }
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: names.applicationInsights
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    IngestionMode: 'LogAnalytics'
    WorkspaceResourceId: workspace.id
    publicNetworkAccessForIngestion: privateMode ? 'Disabled' : 'Enabled'
    publicNetworkAccessForQuery: privateMode ? 'Disabled' : 'Enabled'
  }
}

resource ampls 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' = if (privateMode) {
  name: names.monitorPrivateLinkScope
  location: 'global'
  tags: tags
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'PrivateOnly'
    }
  }
}

resource workspaceScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = if (privateMode) {
  parent: ampls
  name: 'workspace'
  properties: {
    linkedResourceId: workspace.id
  }
}

resource applicationInsightsScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = if (privateMode) {
  parent: ampls
  name: 'application-insights'
  properties: {
    linkedResourceId: applicationInsights.id
  }
}

module amplsPe '../networking/private-endpoint.bicep' = if (privateMode) {
  name: 'monitor-private-endpoint'
  params: {
    name: 'pe-${ampls.name}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: ampls.id
    groupIds: [
      'azuremonitor'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.monitor
      privateDnsZoneIds.oms
      privateDnsZoneIds.ods
      privateDnsZoneIds.agentsvc
      privateDnsZoneIds.blob
    ]
    tags: tags
  }
}

output applicationInsightsId string = applicationInsights.id
output applicationInsightsConnectionString string = applicationInsights.properties.ConnectionString
output workspaceId string = workspace.id
output amplsId string = privateMode ? ampls.id : ''

