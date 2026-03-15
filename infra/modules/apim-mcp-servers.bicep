// ---------------------------------------------------------------------------
// Module: apim-mcp-servers.bicep
// Creates native MCP-type APIs in APIM using the Azure-native MCP Server
// feature (type='mcp' with mcpProperties). These APIs leverage APIM's
// built-in MCP protocol handling — no wildcard operations or custom
// policies needed.
//
// Reference: Azure-Samples/AI-Gateway modules/apim-streamable-mcp/api.bicep
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
// Helper: determine eligibility per server
// ---------------------------------------------------------------------------
var serverEligibility = [for server in mcpServers: {
  name: server.name
  eligible: server.transport == 'streamable-http' && server.type != 'azure-openai' && !contains(server.backendUrl, 'PLACEHOLDER')
  needsMcpBackend: endsWith(server.backendUrl, '/mcp')
}]

// ---------------------------------------------------------------------------
// MCP-specific backends (only for servers whose backendUrl ends with /mcp)
// For correct routing, MCP backends must NOT include /mcp in the URL because
// APIM appends /mcp during native MCP protocol routing.
// ---------------------------------------------------------------------------
resource mcpBackends 'Microsoft.ApiManagement/service/backends@2024-06-01-preview' = [
  for (server, i) in mcpServers: if (serverEligibility[i].eligible && serverEligibility[i].needsMcpBackend) {
    parent: apim
    name: '${server.name}-mcp-backend'
    properties: {
      title: '${server.displayName} (MCP)'
      description: 'MCP-native backend for ${server.displayName}'
      url: replace(server.backendUrl, '/mcp', '')
      protocol: 'http'
      tls: {
        validateCertificateChain: true
        validateCertificateName: true
      }
    }
  }
]

// ---------------------------------------------------------------------------
// Native MCP-type APIs
// ---------------------------------------------------------------------------
resource mcpApis 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = [
  for (server, i) in mcpServers: if (serverEligibility[i].eligible) {
    parent: apim
    name: '${server.name}-mcp-server'
    properties: {
      displayName: '${server.displayName} (MCP)'
      description: '${server.description} (Native MCP Server)'
      type: 'mcp'
      path: '${server.basePath}-mcp-server'
      protocols: [
        'https'
      ]
      subscriptionRequired: true
      subscriptionKeyParameterNames: {
        header: 'Ocp-Apim-Subscription-Key'
        query: 'subscription-key'
      }
      backendId: serverEligibility[i].needsMcpBackend ? '${server.name}-mcp-backend' : '${server.name}-backend'
      isCurrent: true
      mcpProperties: {
        transportType: 'streamable'
      }
    }
    dependsOn: serverEligibility[i].needsMcpBackend ? [mcpBackends[i]] : []
  }
]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output mcpServerNames array = [
  for (server, i) in mcpServers: serverEligibility[i].eligible ? mcpApis[i].name : ''
]
