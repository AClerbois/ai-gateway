// ---------------------------------------------------------------------------
// Module: container-apps.bicep
// Deploys Azure Container Apps Environment and one Container App per
// wrapped stdio MCP server. Each app runs a supergateway container that
// converts stdio → Streamable HTTP so the MCP server can be proxied by APIM.
// ---------------------------------------------------------------------------

@description('Base name for all resources.')
param baseName string

@description('Azure region for deployment.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Log Analytics workspace ID for Container Apps diagnostics.')
param logAnalyticsWorkspaceId string

@description('ACR login server (e.g. myacr.azurecr.io).')
param acrLoginServer string

@description('ACR resource name.')
param acrName string

@description('Array of wrapped MCP server definitions from config.')
param wrappedMcpServers array

// ---------------------------------------------------------------------------
// Reference ACR for credentials
// ---------------------------------------------------------------------------
resource acr 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: acrName
}

// ---------------------------------------------------------------------------
// Container Apps Environment
// ---------------------------------------------------------------------------
resource containerAppsEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: '${baseName}-cae'
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2023-09-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2023-09-01').primarySharedKey
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Container App per wrapped MCP server
// ---------------------------------------------------------------------------
resource containerApps 'Microsoft.App/containerApps@2024-03-01' = [
  for server in wrappedMcpServers: {
    name: '${baseName}-${server.name}'
    location: location
    tags: tags
    properties: {
      managedEnvironmentId: containerAppsEnv.id
      configuration: {
        ingress: {
          external: true
          targetPort: 8000
          transport: 'http'
          allowInsecure: false
        }
        registries: [
          {
            server: acrLoginServer
            username: acr.listCredentials().username
            passwordSecretRef: 'acr-password'
          }
        ]
        secrets: concat(
          [
            {
              name: 'acr-password'
              value: acr.listCredentials().passwords[0].value
            }
          ],
          map(server.envVars, envVar => {
            name: toLower(replace(envVar.name, '_', '-'))
            value: envVar.value
          })
        )
      }
      template: {
        containers: [
          {
            name: server.name
            image: '${acrLoginServer}/${server.imageName}:latest'
            resources: {
              cpu: json('0.5')
              memory: '1Gi'
            }
            env: [
              for envVar in server.envVars: {
                name: envVar.name
                secretRef: toLower(replace(envVar.name, '_', '-'))
              }
            ]
          }
        ]
        scale: {
          minReplicas: 0
          maxReplicas: 3
          rules: [
            {
              name: 'http-scaling'
              http: {
                metadata: {
                  concurrentRequests: '10'
                }
              }
            }
          ]
        }
      }
    }
  }
]

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output containerAppsEnvId string = containerAppsEnv.id
output containerAppFqdns array = [
  for (server, i) in wrappedMcpServers: {
    name: server.name
    fqdn: containerApps[i].properties.configuration.ingress.fqdn
    url: 'https://${containerApps[i].properties.configuration.ingress.fqdn}'
  }
]
