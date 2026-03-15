// ---------------------------------------------------------------------------
// Parameters file for main.bicep
// Customize values below for your environment.
// ---------------------------------------------------------------------------
using 'main.bicep'

param environment = 'dev'
param location = 'westeurope'
param publisherEmail = 'adrien@senseof.tech'
param publisherName = 'Sense of Tech'

// Optional: Entra ID configuration for OAuth 2.1 authentication.
// Leave empty to disable Entra ID validation (subscription keys only).
param entraIdTenantId = ''
param entraIdClientAppIds = ''

// Deploy wrapped stdio MCP servers (GitHub, Azure DevOps, Terraform, Snyk, Fluent UI Blazor)
// on Azure Container Apps. Requires images to be pushed to ACR first.
// See scripts/build-push-images.ps1 and docs/stdio-to-http-guide.md.
param deployWrappedServers = true

// Deploy Azure API Center to catalog and expose MCP APIs.
// Provides a searchable inventory accessible via portal + VS Code extension.
param deployApiCenter = true
