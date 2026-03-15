// ---------------------------------------------------------------------------
// Module: apim-backends.bicep
// Creates APIM backend entities for each MCP server defined in config.
// ---------------------------------------------------------------------------

@description('Name of the existing APIM instance.')
param apimName string

@description('Array of MCP server definitions from config/mcp-servers.json.')
param mcpServers array

// ---------------------------------------------------------------------------
// Reference existing APIM
// ---------------------------------------------------------------------------
resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

// ---------------------------------------------------------------------------
// Backend for each MCP server
// ---------------------------------------------------------------------------
resource backends 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [
  for server in mcpServers: {
    parent: apim
    name: '${server.name}-backend'
    properties: {
      title: server.displayName
      description: server.description
      url: server.backendUrl
      protocol: 'http'
      tls: {
        validateCertificateChain: true
        validateCertificateName: true
      }
    }
  }
]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output backendNames array = [
  for (server, i) in mcpServers: backends[i].name
]
