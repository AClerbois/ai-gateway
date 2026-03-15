// ---------------------------------------------------------------------------
// Module: apim-named-values.bicep
// Stores configuration values in APIM named values for policy references.
// ---------------------------------------------------------------------------

@description('Name of the existing APIM instance.')
param apimName string

@description('Microsoft Entra ID tenant ID for token validation.')
param entraIdTenantId string = ''

@description('Allowed client application IDs (comma-separated).')
param entraIdClientAppIds string = ''

@description('Approved MCP servers from the whitelist (may contain mcpPrimitives).')
param approvedServers array = []

// ---------------------------------------------------------------------------
// Reference existing APIM
// ---------------------------------------------------------------------------
resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

// ---------------------------------------------------------------------------
// Named Values — Entra ID
// ---------------------------------------------------------------------------
resource namedValueTenantId 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = if (!empty(entraIdTenantId)) {
  parent: apim
  name: 'entra-tenant-id'
  properties: {
    displayName: 'entra-tenant-id'
    value: entraIdTenantId
    secret: false
  }
}

resource namedValueClientAppIds 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = if (!empty(entraIdClientAppIds)) {
  parent: apim
  name: 'entra-client-app-ids'
  properties: {
    displayName: 'entra-client-app-ids'
    value: entraIdClientAppIds
    secret: false
  }
}

// ---------------------------------------------------------------------------
// Named Values — MCP Primitives Filter (per server)
// Uses sub-module to work around BCP138 (no nested for + conditional).
// ---------------------------------------------------------------------------
module mcpPrimitivesNamedValues 'apim-named-values-primitives.bicep' = [
  for server in approvedServers: if (contains(server, 'mcpPrimitives')) {
    name: 'nv-primitives-${server.name}'
    params: {
      apimName: apimName
      serverName: server.name
      mcpPrimitivesJson: string(server.mcpPrimitives)
    }
  }
]
