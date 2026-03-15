// ---------------------------------------------------------------------------
// Main Bicep Orchestrator
// Deploys Azure API Management as an AI Gateway for MCP Tools governance.
//
// Architecture:
//   Monitoring (Log Analytics + App Insights)
//     └─► APIM (Developer SKU, SystemAssigned MI, Preview release channel)
//           ├─► Logger → App Insights
//           ├─► Named Values (Entra ID config)
//           ├─► Product: MCP Tools
//           ├─► Backends (per MCP server)
//           ├─► APIs + Policies (per MCP server)
//           └─► Global Policy
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------
@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for deployment.')
param location string = resourceGroup().location

@description('Base name prefix for all resources.')
param baseName string = 'apim-mcp-${environment}'

@description('Publisher email for the APIM instance.')
param publisherEmail string

@description('Publisher name for the APIM instance.')
param publisherName string

@description('Microsoft Entra ID tenant ID for token validation (optional).')
param entraIdTenantId string = ''

@description('Allowed Entra ID client application IDs, comma-separated (optional).')
param entraIdClientAppIds string = ''

@description('Deploy wrapped stdio MCP servers on Container Apps (requires images in ACR).')
param deployWrappedServers bool = true

@description('Deploy Azure API Center to catalog MCP APIs.')
param deployApiCenter bool = true

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------
var tags = {
  project: 'apim-mcp'
  environment: environment
  managedBy: 'bicep'
}

var mcpConfig = loadJsonContent('../config/mcp-servers.json')
var mcpServers = mcpConfig.mcpServers

var globalPolicyXml = loadTextContent('../policies/global-policy.xml')
var mcpPolicyXml = loadTextContent('../policies/mcp-passthrough-policy.xml')
var aoaiPolicyXml = loadTextContent('../policies/aoai-policy.xml')

var wrappedConfig = loadJsonContent('../config/wrapped-mcp-servers.json')
var wrappedMcpServers = wrappedConfig.wrappedMcpServers

var profilesConfig = loadJsonContent('../config/profiles.json')
var profiles = profilesConfig.profiles

var whitelistConfig = loadJsonContent('../config/mcp-whitelist.json')
var approvedServers = whitelistConfig.approvedServers

// ---------------------------------------------------------------------------
// Phase 1: Foundation Infrastructure
// ---------------------------------------------------------------------------
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    baseName: baseName
    location: location
    tags: tags
  }
}

module apim 'modules/apim.bicep' = {
  name: 'apim'
  params: {
    baseName: baseName
    location: location
    publisherEmail: publisherEmail
    publisherName: publisherName
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// Phase 1b: Container Infrastructure (ACR + Container Apps for wrapped servers)
// ---------------------------------------------------------------------------
module acr 'modules/container-registry.bicep' = if (deployWrappedServers) {
  name: 'container-registry'
  params: {
    baseName: baseName
    location: location
    tags: tags
  }
}

module containerApps 'modules/container-apps.bicep' = if (deployWrappedServers) {
  name: 'container-apps'
  params: {
    baseName: baseName
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    acrLoginServer: acr!.outputs.acrLoginServer
    acrName: acr!.outputs.acrName
    wrappedMcpServers: wrappedMcpServers
  }
}

// ---------------------------------------------------------------------------
// Phase 2: APIM Configuration (depends on APIM + Monitoring)
// ---------------------------------------------------------------------------
module apimLogger 'modules/apim-logger.bicep' = {
  name: 'apim-logger'
  params: {
    apimName: apim.outputs.apimName
    appInsightsInstrumentationKey: monitoring.outputs.appInsightsInstrumentationKey
    appInsightsId: monitoring.outputs.appInsightsId
  }
}

module apimNamedValues 'modules/apim-named-values.bicep' = {
  name: 'apim-named-values'
  params: {
    apimName: apim.outputs.apimName
    entraIdTenantId: entraIdTenantId
    entraIdClientAppIds: entraIdClientAppIds
    approvedServers: approvedServers
  }
}

module apimProducts 'modules/apim-products.bicep' = {
  name: 'apim-products'
  params: {
    apimName: apim.outputs.apimName
    profiles: profiles
    mcpServers: mcpServers
  }
}

module apimBackends 'modules/apim-backends.bicep' = {
  name: 'apim-backends'
  params: {
    apimName: apim.outputs.apimName
    mcpServers: mcpServers
  }
}

// ---------------------------------------------------------------------------
// Phase 3: APIs + Policies (depends on Products + Backends)
// ---------------------------------------------------------------------------
module apimApis 'modules/apim-apis.bicep' = {
  name: 'apim-apis'
  params: {
    apimName: apim.outputs.apimName
    mcpServers: mcpServers
    mcpPolicyXml: mcpPolicyXml
    aoaiPolicyXml: aoaiPolicyXml
  }
  dependsOn: [
    apimBackends
    apimLogger
  ]
}

// ---------------------------------------------------------------------------
// Phase 4: API Center (optional catalog)
// ---------------------------------------------------------------------------
module apiCenter 'modules/api-center.bicep' = if (deployApiCenter) {
  name: 'api-center'
  params: {
    baseName: baseName
    location: location
    tags: tags
    mcpServers: mcpServers
    apimGatewayUrl: apim.outputs.apimGatewayUrl
    profiles: profiles
  }
}

// ---------------------------------------------------------------------------
// Global Policy
// ---------------------------------------------------------------------------
module apimGlobalPolicy 'modules/apim-global-policy.bicep' = {
  name: 'apim-global-policy'
  params: {
    apimName: apim.outputs.apimName
    globalPolicyXml: globalPolicyXml
  }
  dependsOn: [
    apimApis
  ]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output apimGatewayUrl string = apim.outputs.apimGatewayUrl
output apimName string = apim.outputs.apimName
output apimPrincipalId string = apim.outputs.apimPrincipalId

output mcpServerEndpoints array = [
  for server in mcpServers: {
    name: server.name
    displayName: server.displayName
    endpoint: '${apim.outputs.apimGatewayUrl}/${server.basePath}'
  }
]

output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
output logAnalyticsWorkspaceId string = monitoring.outputs.logAnalyticsWorkspaceId

output acrLoginServer string = deployWrappedServers ? acr!.outputs.acrLoginServer : ''

output mcpRegistryBaseUrl string = deployApiCenter ? apiCenter!.outputs.mcpRegistryBaseUrl : ''
output containerAppFqdns array = deployWrappedServers ? containerApps!.outputs.containerAppFqdns : []

output apiCenterName string = deployApiCenter ? apiCenter!.outputs.apiCenterName : ''
output apiCenterPortalUrl string = deployApiCenter ? apiCenter!.outputs.apiCenterPortalUrl : ''
