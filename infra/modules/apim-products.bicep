// ---------------------------------------------------------------------------
// Module: apim-products.bicep
// Creates APIM Products based on profiles (Developer, Business Analyst,
// Application 1, Application 2, etc.). Each profile groups a subset of
// MCP APIs with its own subscription key.
// ---------------------------------------------------------------------------

@description('Name of the existing APIM instance.')
param apimName string

@description('Profile definitions from config/profiles.json.')
param profiles array

@description('All MCP server definitions (used for wildcard resolution).')
param mcpServers array

// ---------------------------------------------------------------------------
// Reference existing APIM
// ---------------------------------------------------------------------------
resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

// ---------------------------------------------------------------------------
// Resolve wildcards: profiles with ["*"] get all server names
// ---------------------------------------------------------------------------
var allServerNames = [for s in mcpServers: s.name]

var resolvedProfiles = [
  for profile in profiles: {
    name: profile.name
    displayName: profile.displayName
    description: profile.description
    servers: contains(profile.servers, '*') ? allServerNames : profile.servers
    subscriptionsLimit: profile.subscriptionsLimit
    approvalRequired: profile.approvalRequired
  }
]

// ---------------------------------------------------------------------------
// Products: one per profile
// ---------------------------------------------------------------------------
resource products 'Microsoft.ApiManagement/service/products@2024-06-01-preview' = [
  for profile in resolvedProfiles: {
    parent: apim
    name: profile.name
    properties: {
      displayName: profile.displayName
      description: profile.description
      state: 'published'
      subscriptionRequired: true
      approvalRequired: profile.approvalRequired
      subscriptionsLimit: profile.subscriptionsLimit
    }
  }
]

// ---------------------------------------------------------------------------
// Default subscription per product
// ---------------------------------------------------------------------------
resource subscriptions 'Microsoft.ApiManagement/service/subscriptions@2024-06-01-preview' = [
  for (profile, i) in resolvedProfiles: {
    parent: apim
    name: '${profile.name}-default-sub'
    properties: {
      scope: products[i].id
      displayName: '${profile.displayName} - Default Subscription'
      state: 'active'
      allowTracing: true
    }
  }
]

// ---------------------------------------------------------------------------
// API-to-Product associations (via sub-module, one per profile)
// ---------------------------------------------------------------------------
module productApis 'apim-product-apis.bicep' = [
  for (profile, i) in resolvedProfiles: {
    name: 'product-apis-${profile.name}'
    params: {
      apimName: apimName
      profileName: profile.name
      serverNames: profile.servers
    }
    dependsOn: [
      products[i]
    ]
  }
]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output productNames array = [for (profile, i) in resolvedProfiles: products[i].name]
output productIds array = [for (profile, i) in resolvedProfiles: products[i].id]
