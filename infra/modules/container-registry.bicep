// ---------------------------------------------------------------------------
// Module: container-registry.bicep
// Deploys Azure Container Registry to host Docker images for wrapped
// stdio MCP servers (supergateway containers).
// ---------------------------------------------------------------------------

@description('Base name for all resources.')
param baseName string

@description('Azure region for deployment.')
param location string

@description('Resource tags.')
param tags object = {}

// ---------------------------------------------------------------------------
// Azure Container Registry
// ---------------------------------------------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' = {
  name: replace('${baseName}acr', '-', '')
  location: location
  tags: tags
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output acrId string = acr.id
output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
