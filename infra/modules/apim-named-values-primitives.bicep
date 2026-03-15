// ---------------------------------------------------------------------------
// Sub-module: apim-named-values-primitives.bicep
// Creates a Named Value for MCP primitives filter config per server.
// Called from apim-named-values.bicep to avoid BCP138 nested loops.
// ---------------------------------------------------------------------------

@description('Name of the existing APIM instance.')
param apimName string

@description('MCP server name (used as Named Value key).')
param serverName string

@description('JSON string of the mcpPrimitives filter configuration.')
param mcpPrimitivesJson string

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

resource namedValuePrimitives 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apim
  name: 'mcp-primitives-${serverName}'
  properties: {
    displayName: 'mcp-primitives-${serverName}'
    value: mcpPrimitivesJson
    secret: false
    tags: [
      'mcp-primitives'
      serverName
    ]
  }
}
