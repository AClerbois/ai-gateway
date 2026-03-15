// ---------------------------------------------------------------------------
// Module: api-center.bicep
// Deploys Azure API Center to catalog and expose all MCP APIs available
// through the APIM AI Gateway. Provides a searchable inventory of
// MCP Tools with metadata, profiles, and lifecycle stages.
// ---------------------------------------------------------------------------

@description('Base name for all resources.')
param baseName string

@description('Azure region for deployment.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Array of MCP server definitions from config/mcp-servers.json.')
param mcpServers array

@description('APIM gateway URL for linking APIs to their deployments.')
param apimGatewayUrl string

@description('Array of profile definitions from config/profiles.json.')
param profiles array = []

// ---------------------------------------------------------------------------
// API Center Service
// ---------------------------------------------------------------------------
var apiCenterName = '${baseName}-apic'

resource apiCenter 'Microsoft.ApiCenter/services@2024-06-01-preview' = {
  name: apiCenterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'Free'
  }
}

// ---------------------------------------------------------------------------
// Default workspace (auto-created, referenced as existing)
// ---------------------------------------------------------------------------
resource defaultWorkspace 'Microsoft.ApiCenter/services/workspaces@2024-06-01-preview' = {
  parent: apiCenter
  name: 'default'
  properties: {
    title: 'Default'
    description: 'Default workspace for MCP API catalog.'
  }
}

// ---------------------------------------------------------------------------
// Environment: APIM Gateway
// ---------------------------------------------------------------------------
resource apimEnvironment 'Microsoft.ApiCenter/services/workspaces/environments@2024-06-01-preview' = {
  parent: defaultWorkspace
  name: 'apim-gateway'
  properties: {
    title: 'APIM AI Gateway'
    description: 'Azure API Management AI Gateway exposing governed MCP Tools.'
    kind: 'development'
    server: {
      type: 'Azure API Management'
      managementPortalUri: [
        replace(apimGatewayUrl, '.azure-api.net', '.management.azure-api.net')
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// Metadata schemas: profile tags + transport type
// ---------------------------------------------------------------------------
resource profileMetadataSchema 'Microsoft.ApiCenter/services/metadataSchemas@2024-06-01-preview' = {
  parent: apiCenter
  name: 'mcp-profiles'
  properties: {
    schema: '{"type":"string","title":"MCP Profiles","description":"Profiles that include this API"}'
    assignedTo: [
      {
        entity: 'api'
        required: false
      }
    ]
  }
}

resource transportMetadataSchema 'Microsoft.ApiCenter/services/metadataSchemas@2024-06-01-preview' = {
  parent: apiCenter
  name: 'mcp-transport'
  properties: {
    schema: '{"type":"string","title":"MCP Transport","description":"Transport protocol used by this MCP server"}'
    assignedTo: [
      {
        entity: 'api'
        required: false
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Metadata schema: MCP Registry profile
// ---------------------------------------------------------------------------
resource registryProfileMetadataSchema 'Microsoft.ApiCenter/services/metadataSchemas@2024-06-01-preview' = {
  parent: apiCenter
  name: 'mcp-registry-profile'
  properties: {
    schema: '{"type":"string","title":"MCP Registry Profile","description":"Profile used as registry name for GitHub MCP Allowlist integration"}'
    assignedTo: [
      {
        entity: 'api'
        required: false
      }
    ]
  }
}

// ---------------------------------------------------------------------------
// Register each MCP server as an API
// ---------------------------------------------------------------------------
resource apiCenterApis 'Microsoft.ApiCenter/services/workspaces/apis@2024-06-01-preview' = [
  for server in mcpServers: {
    parent: defaultWorkspace
    name: server.name
    properties: {
      title: server.displayName
      description: server.description
      kind: server.type == 'azure-openai' ? 'rest' : 'rest'
      externalDocumentation: [
        {
          title: 'Gateway Endpoint'
          url: '${apimGatewayUrl}/${server.basePath}'
        }
      ]
      customProperties: {
        'mcp-transport': server.transport
      }
    }
  }
]

// ---------------------------------------------------------------------------
// API versions (v1 for each MCP server)
// ---------------------------------------------------------------------------
resource apiVersions 'Microsoft.ApiCenter/services/workspaces/apis/versions@2024-06-01-preview' = [
  for (server, i) in mcpServers: {
    parent: apiCenterApis[i]
    name: 'v1-0'
    properties: {
      title: 'v1.0'
      lifecycleStage: 'production'
    }
  }
]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output apiCenterName string = apiCenter.name
output apiCenterPortalUrl string = 'https://${apiCenterName}.data.${location}.azure-apicenter.ms'
output mcpRegistryBaseUrl string = 'https://${apiCenterName}.data.${location}.azure-apicenter.ms'
output mcpRegistryProfiles array = [
  for profile in profiles: {
    name: profile.name
    displayName: profile.displayName
    registryUrl: 'https://${apiCenterName}.data.${location}.azure-apicenter.ms'
  }
]
