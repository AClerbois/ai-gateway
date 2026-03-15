// ---------------------------------------------------------------------------
// Module: apim-logger.bicep
// Configures APIM logger linked to Application Insights and enables
// diagnostic settings for request/response monitoring.
// ---------------------------------------------------------------------------

@description('Name of the existing APIM instance.')
param apimName string

@description('Application Insights instrumentation key.')
param appInsightsInstrumentationKey string

@description('Application Insights resource ID.')
param appInsightsId string

// ---------------------------------------------------------------------------
// Reference existing APIM
// ---------------------------------------------------------------------------
resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' existing = {
  name: apimName
}

// ---------------------------------------------------------------------------
// APIM Logger → Application Insights
// ---------------------------------------------------------------------------
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2024-06-01-preview' = {
  parent: apim
  name: 'appinsights-logger'
  properties: {
    loggerType: 'applicationInsights'
    resourceId: appInsightsId
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
  }
}

// ---------------------------------------------------------------------------
// APIM Diagnostic → Application Insights
// ---------------------------------------------------------------------------
resource apimDiagnostic 'Microsoft.ApiManagement/service/diagnostics@2024-06-01-preview' = {
  parent: apim
  name: 'applicationinsights'
  properties: {
    loggerId: apimLogger.id
    alwaysLog: 'allErrors'
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: [
          'Mcp-Session-Id'
          'X-Forwarded-For'
        ]
        body: {
          bytes: 8192
        }
      }
      response: {
        headers: [
          'Content-Type'
        ]
        body: {
          bytes: 0 // MCP servers require 0 to avoid response buffering
        }
      }
    }
    backend: {
      request: {
        headers: [
          'Mcp-Session-Id'
        ]
        body: {
          bytes: 8192
        }
      }
      response: {
        headers: [
          'Content-Type'
        ]
        body: {
          bytes: 0
        }
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
output loggerId string = apimLogger.id
