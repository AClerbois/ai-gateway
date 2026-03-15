# Architecture Documentation

## Overview

This project deploys Azure API Management as an **AI Gateway** to centralize governance, security, and monitoring for MCP (Model Context Protocol) servers and Azure OpenAI endpoints.

## Data Flow

```
                              ┌─────────────────────────┐
                              │   VS Code / Copilot     │
                              │   MCP Client            │
                              └────────┬────────────────┘
                                       │ HTTPS (Streamable HTTP)
                                       │ + Ocp-Apim-Subscription-Key
                                       │ + Mcp-Session-Id
                                       ▼
                         ┌─────────────────────────────────┐
                         │       Azure API Management      │
                         │      (AI Gateway - Developer)   │
                         │                                 │
                         │  ┌─────────────────────────┐    │
                         │  │    Global Policy         │    │
                         │  │  - CORS                  │    │
                         │  │  - emit-metric           │    │
                         │  │  - trace                 │    │
                         │  └─────────────────────────┘    │
                         │                                 │
  ┌──────────────────────┼─────────────────────────────────┼──────────────────────┐
  │                      │                                 │                      │
  ▼                      ▼                                 ▼                      │
┌────────────┐   ┌────────────────┐               ┌──────────────┐               │
│ mslearn-mcp│   │  custom-mcp    │               │   aoai-api   │               │
│ API        │   │  API           │               │   API        │               │
│            │   │                │               │              │               │
│ Policy:    │   │ Policy:        │               │ Policy:      │               │
│ mcp-pass-  │   │ mcp-pass-     │               │ aoai-policy  │               │
│ through    │   │ through       │               │ - token limit│               │
│ - rate-    │   │ - rate-       │               │ - MI auth    │               │
│   limit    │   │   limit       │               │ - token      │               │
│ - trace    │   │ - trace       │               │   metrics    │               │
└────┬───────┘   └──────┬────────┘               └──────┬───────┘               │
     │                  │                               │                       │
     ▼                  ▼                               ▼                       │
┌────────────┐  ┌───────────────┐               ┌──────────────┐               │
│ MS Learn   │  │ Custom MCP    │               │ Azure OpenAI │               │
│ MCP Server │  │ Server        │               │ Service      │               │
│ (External) │  │ (Azure hosted)│               │              │               │
└────────────┘  └───────────────┘               └──────────────┘               │
                                                                               │
                         ┌─────────────────────────────────┐                   │
                         │       Azure Monitor             │◄──────────────────┘
                         │  ┌───────────────────────────┐  │   Diagnostics
                         │  │  Application Insights     │  │   + Metrics
                         │  │  - Request traces         │  │
                         │  │  - Token usage metrics    │  │
                         │  │  - Error tracking         │  │
                         │  └───────────────────────────┘  │
                         │  ┌───────────────────────────┐  │
                         │  │  Log Analytics Workspace  │  │
                         │  │  - 90-day retention       │  │
                         │  │  - KQL queries            │  │
                         │  └───────────────────────────┘  │
                         └─────────────────────────────────┘
```

## Policy Chain

Each request passes through policies in this order:

### 1. Global Policy (all APIs)

| Policy | Purpose |
|--------|---------|
| `cors` | Allow CORS for local dev (localhost:3000, vscode.dev, portal.azure.com) |
| `emit-metric` | Count requests with dimensions: API ID, Subscription ID, Client IP, Operation |
| `trace` | Log request details (method, path, API name, subscription) |

### 2. API-Level Policy (per server type)

#### MCP Passthrough (`mcp-passthrough-policy.xml`)

| Policy | Purpose |
|--------|---------|
| `validate-azure-ad-token` | *(Optional)* Validate Entra ID JWT tokens |
| `rate-limit-by-key` | Limit requests per MCP session (keyed on `Mcp-Session-Id` header, fallback to IP) |
| `trace` | Log MCP session details |
| `set-backend-service` | Route to correct backend based on API name |
| `set-header` (outbound) | Forward `Mcp-Session-Id` in response |

#### Azure OpenAI (`aoai-policy.xml`)

| Policy | Purpose |
|--------|---------|
| `validate-azure-ad-token` | *(Optional)* Validate caller's Entra ID JWT |
| `llm-token-limit` | Enforce tokens-per-minute quota (per subscription) |
| `authentication-managed-identity` | Authenticate to Azure OpenAI with APIM's managed identity |
| `llm-emit-token-metric` (outbound) | Emit token usage metrics (prompt + completion tokens) |

## Security Model

### Inbound Authentication (Client → APIM)

1. **Subscription Key** (always active): Clients must send `Ocp-Apim-Subscription-Key` header. Keys are managed through the "MCP Tools" product.

2. **Entra ID OAuth 2.1** (optional): When enabled, clients must also present a valid JWT bearer token. The `validate-azure-ad-token` policy validates:
   - Token issuer matches the configured tenant
   - Client application ID is in the allowed list
   - Token is not expired

### Outbound Authentication (APIM → Backend)

- **Azure OpenAI**: APIM uses its SystemAssigned managed identity with `authentication-managed-identity` policy (resource: `https://cognitiveservices.azure.com`)
- **Third-party / Custom MCP**: Pass-through (backend handles its own auth if needed)

### TLS Hardening

Legacy protocols and weak ciphers are disabled at the APIM level:
- SSL 3.0, TLS 1.0, TLS 1.1 disabled
- TripleDES and RSA-CBC ciphers disabled
- HTTP/2 enabled

## Monitoring

### Application Insights

| Data | Details |
|------|---------|
| Request traces | Method, path, status code, duration |
| Headers logged | `Mcp-Session-Id`, `X-Forwarded-For`, `Content-Type` |
| Request body | Logged (up to 8 KB) for debugging |
| Response body | **Not logged** (set to 0 bytes) — required for MCP streaming |
| Custom metrics | `mcp-gateway-requests` (request count), token usage (Azure OpenAI) |
| Sampling | 100% (all requests captured) |

### Log Analytics

- 90-day retention
- KQL query support for advanced analysis

### Example KQL Queries

```kql
// MCP requests by session
requests
| where customDimensions["API ID"] != ""
| summarize count() by tostring(customDimensions["Mcp-Session-Id"]), bin(timestamp, 1h)
| render timechart

// Token usage by subscription
customMetrics
| where name == "Total Tokens"
| summarize sum(value) by tostring(customDimensions["Subscription ID"]), bin(timestamp, 1d)
| render columnchart

// Error rate by API
requests
| where resultCode >= 400
| summarize Errors=count() by name, bin(timestamp, 1h)
| render timechart
```

## Adding a New MCP Server

1. **Add entry to `config/mcp-servers.json`**:
   ```json
   {
     "name": "my-new-mcp",
     "displayName": "My New MCP Server",
     "description": "Description of the server.",
     "type": "custom",
     "backendUrl": "https://my-new-mcp.azurewebsites.net",
     "transport": "streamable-http",
     "basePath": "my-new-mcp",
     "rateLimitPerMinute": 60
   }
   ```

2. **Redeploy**: `az deployment group create --template-file infra/main.bicep --parameters infra/main.bicepparam`

3. **Regenerate workspace config**: Run `scripts/generate-mcp-config.ps1`

The Bicep loop in `apim-apis.bicep` and `apim-backends.bicep` automatically creates the API, backend, operations, policies, and product association for each entry.

## Bicep Module Dependency Graph

```
monitoring.bicep ──────────────┐
                               ▼
apim.bicep ───────────► apim-logger.bicep
    │                          
    ├──────────────────► apim-named-values.bicep
    │
    ├──────────────────► apim-products.bicep ──► apim-apis.bicep
    │                                                   ▲
    └──────────────────► apim-backends.bicep ────────────┘
                                                        │
                                              Global Policy (main.bicep)
```
