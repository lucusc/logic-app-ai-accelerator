param location string
param tags object
param networkMode string
@description('Resolved resource names from main.bicep.')
param names object
@description('Web App Service plan SKU: { name, tier?, capacity? }.')
param webAppPlanSku object
@description('Logic App plan SKU: { name, tier?, capacity? }.')
param logicAppPlanSku object
param webAppServiceEnvironmentId string = ''
param logicAppServiceEnvironmentId string = ''
param corsAllowedOrigins string[] = []
param allowedIpRanges string[] = []
param privateEndpointSubnetId string = ''
param webIntegrationSubnetId string = ''
param logicIntegrationSubnetId string = ''
param privateDnsZoneIds object = {}
param storageBlobEndpoint string
param logicStorageId string
param cosmosEndpoint string
param registryLoginServer string
param webContainerImage string = ''
param foundryOpenAiEndpoint string
param documentIntelligenceEndpoint string
param searchEndpoint string
param modelDeploymentName string
param monitoringMode string
param applicationInsightsConnectionString string = ''
param logAnalyticsWorkspaceId string = ''
param tenantId string = tenant().tenantId
param authTenantId string = tenantId
param enableAppServiceAuth bool = false
param appServiceAuthClientId string = ''
param backendApiAudience string = 'api://logic-app-ai-accelerator'

var privateMode = networkMode == 'private'
var webUsesAse = !empty(webAppServiceEnvironmentId)
var logicUsesAse = !empty(logicAppServiceEnvironmentId)
var webPrivateEndpointEnabled = privateMode && !webUsesAse
var logicPrivateEndpointEnabled = privateMode && !logicUsesAse
var containerImage = !empty(webContainerImage) ? webContainerImage : '${registryLoginServer}/accelerator:latest'

// The web host name is computed so the Logic App does not depend on the web app,
// which lets the web app allow-list the Logic App outbound addresses.
var appServiceDomainSuffix = environment().name == 'AzureUSGovernment'
  ? 'azurewebsites.us'
  : environment().name == 'AzureChinaCloud' ? 'chinacloudsites.cn' : 'azurewebsites.net'
var webAseIdSegments = split(webAppServiceEnvironmentId, '/')
resource webAse 'Microsoft.Web/hostingEnvironments@2024-04-01' existing = if (webUsesAse) {
  name: webUsesAse ? last(webAseIdSegments) : 'unused'
  scope: resourceGroup(webUsesAse ? webAseIdSegments[2] : subscription().subscriptionId, webUsesAse ? webAseIdSegments[4] : resourceGroup().name)
}
var webHostName = webUsesAse ? '${names.webApp}.${webAse!.properties.dnsSuffix}' : '${names.webApp}.${appServiceDomainSuffix}'

var userIpRules = [
  for (range, index) in allowedIpRanges: {
    name: 'allow-${index}'
    ipAddress: range
    action: 'Allow'
    priority: 100 + index
  }
]

resource webIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.webIdentity
  location: location
  tags: tags
}

resource logicIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: names.logicIdentity
  location: location
  tags: tags
}

resource logicPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: names.logicAppPlan
  location: location
  tags: tags
  kind: logicUsesAse ? 'windows' : 'elastic'
  sku: union(
    {
      name: logicAppPlanSku.name
      capacity: logicAppPlanSku.?capacity ?? 1
    },
    empty(logicAppPlanSku.?tier ?? '') ? {} : { tier: logicAppPlanSku.tier }
  )
  properties: {
    hostingEnvironmentProfile: logicUsesAse ? { id: logicAppServiceEnvironmentId } : null
    reserved: false
  }
}

module logic 'br/public:avm/res/web/site:0.16.0' = {
  name: 'logic-app'
  params: {
    name: names.logicApp
    location: location
    tags: union(tags, {
      'azd-service-name': 'logic'
    })
    kind: 'functionapp,workflowapp'
    serverFarmResourceId: logicPlan.id
    appServiceEnvironmentResourceId: logicUsesAse ? logicAppServiceEnvironmentId : null
    managedIdentities: {
      systemAssigned: true
      userAssignedResourceIds: [
        logicIdentity.id
      ]
    }
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
    virtualNetworkSubnetId: privateMode && !logicUsesAse ? logicIntegrationSubnetId : null
    vnetContentShareEnabled: privateMode && !logicUsesAse
    vnetImagePullEnabled: privateMode && !logicUsesAse
    vnetRouteAllEnabled: privateMode && !logicUsesAse
    storageAccountRequired: true
    configs: [
      {
        name: 'appsettings'
        retainCurrentAppSettings: true
        storageAccountResourceId: logicStorageId
        storageAccountUseIdentityAuthentication: true
        properties: {
          APP_KIND: 'workflowApp'
          APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsightsConnectionString
          FUNCTIONS_EXTENSION_VERSION: '~4'
          FUNCTIONS_WORKER_RUNTIME: 'dotnet'
          WEBSITE_NODE_DEFAULT_VERSION: '~20'
          WORKFLOWS_LOCATION_NAME: location
          WORKFLOWS_MANAGEMENT_BASE_URI: environment().resourceManager
          WORKFLOWS_RESOURCE_GROUP_NAME: resourceGroup().name
          WORKFLOWS_SUBSCRIPTION_ID: subscription().subscriptionId
          WORKFLOWS_TENANT_ID: tenantId
          AZURE_STORAGE_ENDPOINT: storageBlobEndpoint
          AZURE_STORAGE_SUBMISSIONS_CONTAINER: 'documents'
          BACKEND_API_URL: 'https://${webHostName}'
          BACKEND_API_AUDIENCE: backendApiAudience
          AzureWebJobsStorage__credential: 'managedidentity'
          AzureWebJobsStorage__managedIdentityResourceId: logicIdentity.id
          WORKFLOWS_IDENTITY_RESOURCE_ID: logicIdentity.id
        }
      }
    ]
    siteConfig: {
      alwaysOn: true
      functionsRuntimeScaleMonitoringEnabled: !logicUsesAse
      ipSecurityRestrictions: userIpRules
      ipSecurityRestrictionsDefaultAction: empty(allowedIpRanges) ? 'Allow' : 'Deny'
      minTlsVersion: '1.2'
      scmIpSecurityRestrictionsUseMain: false
      use32BitWorkerProcess: false
    }
  }
}

resource logicSite 'Microsoft.Web/sites@2024-04-01' existing = {
  name: names.logicApp
}

// When an IP allow-list is set, the Logic App must still reach the API.
var logicOutboundIpRules = empty(allowedIpRanges)
  ? []
  : map(split(logicSite.properties.possibleOutboundIpAddresses, ','), ip => {
      name: 'logic-app-outbound'
      ipAddress: '${trim(ip)}/32'
      action: 'Allow'
      priority: 200
    })

resource webPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: names.webAppPlan
  location: location
  tags: tags
  kind: 'linux'
  sku: union(
    {
      name: webAppPlanSku.name
      capacity: webAppPlanSku.?capacity ?? 1
    },
    empty(webAppPlanSku.?tier ?? '') ? {} : { tier: webAppPlanSku.tier }
  )
  properties: {
    hostingEnvironmentProfile: webUsesAse ? { id: webAppServiceEnvironmentId } : null
    reserved: true
  }
}

resource web 'Microsoft.Web/sites@2024-04-01' = {
  name: names.webApp
  location: location
  tags: union(tags, {
    'azd-service-name': 'web'
  })
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${webIdentity.id}': {}
    }
  }
  properties: {
    clientAffinityEnabled: false
    hostingEnvironmentProfile: webUsesAse ? { id: webAppServiceEnvironmentId } : null
    httpsOnly: true
    publicNetworkAccess: privateMode ? 'Disabled' : 'Enabled'
    serverFarmId: webPlan.id
    virtualNetworkSubnetId: privateMode && !webUsesAse ? webIntegrationSubnetId : null
    vnetImagePullEnabled: privateMode && !webUsesAse
    vnetRouteAllEnabled: privateMode && !webUsesAse
    siteConfig: {
      acrUseManagedIdentityCreds: true
      alwaysOn: true
      cors: empty(corsAllowedOrigins)
        ? null
        : {
            allowedOrigins: corsAllowedOrigins
            supportCredentials: false
          }
      ftpsState: 'Disabled'
      http20Enabled: true
      ipSecurityRestrictions: concat(userIpRules, logicOutboundIpRules)
      ipSecurityRestrictionsDefaultAction: empty(allowedIpRanges) ? 'Allow' : 'Deny'
      linuxFxVersion: 'DOCKER|${containerImage}'
      minTlsVersion: '1.2'
      scmIpSecurityRestrictionsUseMain: false
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: applicationInsightsConnectionString
        }
        {
          name: 'AZURE_TENANT_ID'
          value: tenantId
        }
        {
          name: 'AZURE_STORAGE_ENDPOINT'
          value: storageBlobEndpoint
        }
        {
          name: 'AZURE_STORAGE_SUBMISSIONS_CONTAINER'
          value: 'documents'
        }
        {
          name: 'AZURE_COSMOS_ENDPOINT'
          value: cosmosEndpoint
        }
        {
          name: 'AZURE_COSMOS_DATABASE'
          value: 'accelerator'
        }
        {
          name: 'AZURE_COSMOS_CONTAINER'
          value: 'jobs'
        }
        {
          name: 'AZURE_DOCUMENT_INTELLIGENCE_ENDPOINT'
          value: documentIntelligenceEndpoint
        }
        {
          name: 'AZURE_SEARCH_ENDPOINT'
          value: searchEndpoint
        }
        {
          name: 'AZURE_SEARCH_INDEX'
          value: 'documents'
        }
        {
          name: 'AZURE_FOUNDRY_OPENAI_ENDPOINT'
          value: foundryOpenAiEndpoint
        }
        {
          name: 'AZURE_MODEL_DEPLOYMENT'
          value: modelDeploymentName
        }
        {
          name: 'BACKEND_API_AUDIENCE'
          value: backendApiAudience
        }
        {
          // App Service authentication uses this identity as a federated credential instead of a client secret.
          name: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID'
          value: enableAppServiceAuth ? webIdentity.properties.clientId : ''
        }
        {
          name: 'WEBSITES_PORT'
          value: '8000'
        }
      ]
    }
  }
  // Reading the Logic App outbound addresses requires the Logic App to exist first.
  dependsOn: [
    logic
  ]
}

resource webAuth 'Microsoft.Web/sites/config@2024-04-01' = if (enableAppServiceAuth) {
  parent: web
  name: 'authsettingsV2'
  properties: {
    globalValidation: {
      requireAuthentication: true
      unauthenticatedClientAction: 'RedirectToLoginPage'
      redirectToProvider: 'azureactivedirectory'
      excludedPaths: [
        '/api/health'
      ]
    }
    httpSettings: {
      requireHttps: true
    }
    identityProviders: {
      azureActiveDirectory: {
        enabled: true
        registration: {
          clientId: appServiceAuthClientId
          clientSecretSettingName: 'OVERRIDE_USE_MI_FIC_ASSERTION_CLIENTID'
          openIdIssuer: '${environment().authentication.loginEndpoint}${authTenantId}/v2.0'
        }
        validation: {
          allowedAudiences: [
            'api://${appServiceAuthClientId}'
            appServiceAuthClientId
          ]
          defaultAuthorizationPolicy: {
            allowedApplications: [
              appServiceAuthClientId
              logicIdentity.properties.clientId
            ]
          }
        }
      }
    }
    platform: {
      enabled: true
    }
  }
}

resource webFtpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: web
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource webScmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: web
  name: 'scm'
  properties: {
    allow: false
  }
}

resource webDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (monitoringMode != 'none') {
  name: 'default'
  scope: web
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
    workspaceId: logAnalyticsWorkspaceId
  }
}

module webPe '../networking/private-endpoint.bicep' = if (webPrivateEndpointEnabled) {
  name: 'web-private-endpoint'
  params: {
    name: 'pe-${web.name}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: web.id
    groupIds: [
      'sites'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.sites
    ]
    tags: tags
  }
}

module logicPe '../networking/private-endpoint.bicep' = if (logicPrivateEndpointEnabled) {
  name: 'logic-private-endpoint'
  params: {
    name: 'pe-${names.logicApp}'
    location: location
    subnetId: privateEndpointSubnetId
    serviceId: logic.outputs.resourceId
    groupIds: [
      'sites'
    ]
    privateDnsZoneIds: [
      privateDnsZoneIds.sites
    ]
    tags: tags
  }
}

output webName string = web.name
output webUri string = 'https://${webHostName}'
output logicName string = logic.outputs.name
output webPrincipalId string = web.identity.principalId
output webIdentityPrincipalId string = webIdentity.properties.principalId
output webIdentityClientId string = webIdentity.properties.clientId
output logicPrincipalId string = logicIdentity.properties.principalId
output logicIdentityClientId string = logicIdentity.properties.clientId
