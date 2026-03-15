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

resource apiCenter 'Microsoft.ApiCenter/services@2024-03-01' = {
  name: apiCenterName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
}

// ---------------------------------------------------------------------------
// Default workspace (auto-created, referenced as existing)
// ---------------------------------------------------------------------------
resource defaultWorkspace 'Microsoft.ApiCenter/services/workspaces@2024-03-01' = {
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
resource apimEnvironment 'Microsoft.ApiCenter/services/workspaces/environments@2024-03-01' = {
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
resource profileMetadataSchema 'Microsoft.ApiCenter/services/metadataSchemas@2024-03-01' = {
  parent: apiCenter
  name: 'mcp-profiles'
  properties: {
    schema: '{"type":"string","title":"MCP Profiles","description":"Profiles that include this API","enum":["all-mcp-tools","developer","business-analyst","app-1","app-2"]}'
    assignedTo: [
      {
        entity: 'api'
        required: false
      }
    ]
  }
}

resource transportMetadataSchema 'Microsoft.ApiCenter/services/metadataSchemas@2024-03-01' = {
  parent: apiCenter
  name: 'mcp-transport'
  properties: {
    schema: '{"type":"string","title":"MCP Transport","description":"Transport protocol used by this MCP server","enum":["streamable-http","https","stdio-wrapped"]}'
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
resource registryProfileMetadataSchema 'Microsoft.ApiCenter/services/metadataSchemas@2024-03-01' = {
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
resource apiCenterApis 'Microsoft.ApiCenter/services/workspaces/apis@2024-03-01' = [
  for server in mcpServers: {
    parent: defaultWorkspace
    name: server.name
    properties: {
      title: server.displayName
      description: server.description
      kind: server.type == 'azure-openai' ? 'rest' : 'rest'
      lifecycleStage: 'production'
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
resource apiVersions 'Microsoft.ApiCenter/services/workspaces/apis/versions@2024-03-01' = [
  for (server, i) in mcpServers: {
    parent: apiCenterApis[i]
    name: 'v1'
    properties: {
      title: 'v1'
    }
  }
]

// ---------------------------------------------------------------------------
// API deployments (link to APIM environment)
// ---------------------------------------------------------------------------
resource apiDeployments 'Microsoft.ApiCenter/services/workspaces/apis/deployments@2024-03-01' = [
  for (server, i) in mcpServers: {
    parent: apiCenterApis[i]
    name: '${server.name}-apim'
    properties: {
      title: 'APIM Gateway'
      description: 'Deployed via Azure API Management AI Gateway.'
      environmentId: apimEnvironment.id
      server: {
        runtimeUri: [
          '${apimGatewayUrl}/${server.basePath}'
        ]
      }
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
