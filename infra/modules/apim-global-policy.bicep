// ---------------------------------------------------------------------------
// Module: apim-global-policy.bicep
// Applies the global XML policy to the APIM instance.
// ---------------------------------------------------------------------------

@description('Name of the existing APIM instance.')
param apimName string

@description('Global policy XML content.')
param globalPolicyXml string

// ---------------------------------------------------------------------------
// Reference existing APIM
// ---------------------------------------------------------------------------
resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

// ---------------------------------------------------------------------------
// Global Policy
// ---------------------------------------------------------------------------
resource globalPolicy 'Microsoft.ApiManagement/service/policies@2024-06-01-preview' = {
  parent: apim
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: globalPolicyXml
  }
}
