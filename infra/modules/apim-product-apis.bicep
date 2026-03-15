// ---------------------------------------------------------------------------
// Module: apim-product-apis.bicep
// Associates MCP APIs to a single APIM product (profile).
// Called once per profile from apim-products.bicep.
// ---------------------------------------------------------------------------

@description('Name of the existing APIM instance.')
param apimName string

@description('Product (profile) name.')
param profileName string

@description('Server names to associate with this product.')
param serverNames array

// ---------------------------------------------------------------------------
// API-to-Product associations
// ---------------------------------------------------------------------------
resource apiProductAssociations 'Microsoft.ApiManagement/service/products/apis@2024-06-01-preview' = [
  for serverName in serverNames: {
    name: '${apimName}/${profileName}/${serverName}-api'
  }
]
