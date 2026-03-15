// ---------------------------------------------------------------------------
// Module: apim-apis.bicep
// Creates passthrough APIs in APIM for each MCP server and associates them
// to the "MCP Tools" product. Each API uses wildcard operations to proxy the
// MCP protocol transparently (Streamable HTTP / JSON-RPC 2.0).
// ---------------------------------------------------------------------------

@description('Name of the existing APIM instance.')
param apimName string

@description('Array of MCP server definitions from config/mcp-servers.json.')
param mcpServers array

@description('MCP passthrough policy XML content.')
param mcpPolicyXml string

@description('Azure OpenAI policy XML content.')
param aoaiPolicyXml string

// ---------------------------------------------------------------------------
// Reference existing APIM
// ---------------------------------------------------------------------------
resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

// ---------------------------------------------------------------------------
// API for each MCP server
// ---------------------------------------------------------------------------
resource apis 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = [
  for server in mcpServers: {
    parent: apim
    name: '${server.name}-api'
    properties: {
      displayName: server.displayName
      description: server.description
      path: server.basePath
      serviceUrl: server.backendUrl
      protocols: [
        'https'
      ]
      subscriptionRequired: true
      subscriptionKeyParameterNames: {
        header: 'Ocp-Apim-Subscription-Key'
        query: 'subscription-key'
      }
      isCurrent: true
    }
  }
]

// ---------------------------------------------------------------------------
// Wildcard operations for MCP passthrough APIs (non-Azure OpenAI)
// ---------------------------------------------------------------------------
resource mcpWildcardGet 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = [
  for (server, i) in mcpServers: if (server.type != 'azure-openai') {
    parent: apis[i]
    name: 'mcp-wildcard-get'
    properties: {
      displayName: 'MCP Wildcard GET'
      method: 'GET'
      urlTemplate: '/*'
    }
  }
]

resource mcpWildcardPost 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = [
  for (server, i) in mcpServers: if (server.type != 'azure-openai') {
    parent: apis[i]
    name: 'mcp-wildcard-post'
    properties: {
      displayName: 'MCP Wildcard POST'
      method: 'POST'
      urlTemplate: '/*'
    }
  }
]

resource mcpWildcardDelete 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = [
  for (server, i) in mcpServers: if (server.type != 'azure-openai') {
    parent: apis[i]
    name: 'mcp-wildcard-delete'
    properties: {
      displayName: 'MCP Wildcard DELETE'
      method: 'DELETE'
      urlTemplate: '/*'
    }
  }
]

// ---------------------------------------------------------------------------
// Azure OpenAI operations (chat completions)
// ---------------------------------------------------------------------------
resource aoaiChatCompletions 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = [
  for (server, i) in mcpServers: if (server.type == 'azure-openai') {
    parent: apis[i]
    name: 'chat-completions'
    properties: {
      displayName: 'Chat Completions'
      method: 'POST'
      urlTemplate: '/deployments/{deployment-id}/chat/completions?api-version={api-version}'
      templateParameters: [
        {
          name: 'deployment-id'
          required: true
          type: 'string'
        }
        {
          name: 'api-version'
          required: true
          type: 'string'
        }
      ]
    }
  }
]

resource aoaiEmbeddings 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = [
  for (server, i) in mcpServers: if (server.type == 'azure-openai') {
    parent: apis[i]
    name: 'embeddings'
    properties: {
      displayName: 'Embeddings'
      method: 'POST'
      urlTemplate: '/deployments/{deployment-id}/embeddings?api-version={api-version}'
      templateParameters: [
        {
          name: 'deployment-id'
          required: true
          type: 'string'
        }
        {
          name: 'api-version'
          required: true
          type: 'string'
        }
      ]
    }
  }
]

// ---------------------------------------------------------------------------
// API-level policies
// ---------------------------------------------------------------------------
resource mcpApiPolicies 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = [
  for (server, i) in mcpServers: if (server.type != 'azure-openai') {
    parent: apis[i]
    name: 'policy'
    properties: {
      format: 'rawxml'
      value: mcpPolicyXml
    }
  }
]

resource aoaiApiPolicies 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = [
  for (server, i) in mcpServers: if (server.type == 'azure-openai') {
    parent: apis[i]
    name: 'policy'
    properties: {
      format: 'rawxml'
      value: aoaiPolicyXml
    }
  }
]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output apiNames array = [
  for (server, i) in mcpServers: apis[i].name
]
