// ---------------------------------------------------------------------------
// Module: apim-product-mcp-apis.bicep
// Associates native MCP Server APIs to a single APIM product (profile).
// Called once per profile from apim-products.bicep.
// Only associates servers that are eligible for MCP (streamable-http,
// non-AOAI, non-placeholder).
// ---------------------------------------------------------------------------

@description('Name of the existing APIM instance.')
param apimName string

@description('Product (profile) name.')
param profileName string

@description('Server names to associate with this product.')
param serverNames array

@description('All MCP server definitions (for eligibility filtering).')
param mcpServers array

// ---------------------------------------------------------------------------
// Build lookup of eligible server names
// ---------------------------------------------------------------------------
var eligibleNames = [for server in mcpServers: server.transport == 'streamable-http' && server.type != 'azure-openai' && !contains(server.backendUrl, 'PLACEHOLDER') ? server.name : '']

// ---------------------------------------------------------------------------
// MCP API-to-Product associations (conditional on eligibility)
// ---------------------------------------------------------------------------
resource mcpApiProductAssociations 'Microsoft.ApiManagement/service/products/apis@2024-06-01-preview' = [
  for serverName in serverNames: if (contains(eligibleNames, serverName)) {
    name: '${apimName}/${profileName}/${serverName}-mcp-server'
  }
]
