<#
.SYNOPSIS
    Generates .vscode/mcp.json from APIM deployment outputs.

.DESCRIPTION
    Reads the APIM gateway URL and MCP server endpoints from the deployment
    outputs and generates a .vscode/mcp.json file so VS Code / Copilot agent
    mode can consume MCP tools through the governed APIM gateway.

.PARAMETER ResourceGroupName
    Name of the Azure resource group containing the APIM instance.

.PARAMETER DeploymentName
    Name of the Bicep deployment to read outputs from.

.PARAMETER SubscriptionKey
    APIM subscription key (Ocp-Apim-Subscription-Key) for authentication.

.EXAMPLE
    .\generate-mcp-config.ps1 -ResourceGroupName "rg-apim-mcp-dev" -DeploymentName "main" -SubscriptionKey "<key>"
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory)]
    [string]$DeploymentName,

    [Parameter(Mandatory)]
    [string]$SubscriptionKey
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Retrieve deployment outputs
Write-Host "Reading deployment outputs from '$DeploymentName' in '$ResourceGroupName'..." -ForegroundColor Cyan
$deployment = az deployment group show `
    --resource-group $ResourceGroupName `
    --name $DeploymentName `
    --query "properties.outputs" `
    --output json | ConvertFrom-Json

$gatewayUrl = $deployment.apimGatewayUrl.value
$mcpEndpoints = $deployment.mcpServerEndpoints.value

Write-Host "Gateway URL: $gatewayUrl" -ForegroundColor Green

# Build .vscode/mcp.json
$servers = @{}

foreach ($endpoint in $mcpEndpoints) {
    # Skip Azure OpenAI endpoints (not MCP protocol)
    $configEntry = (Get-Content -Raw -Path "$PSScriptRoot\..\config\mcp-servers.json" | ConvertFrom-Json).mcpServers |
        Where-Object { $_.name -eq $endpoint.name }

    if ($configEntry.type -eq 'azure-openai') {
        Write-Host "Skipping Azure OpenAI endpoint: $($endpoint.name) (not MCP protocol)" -ForegroundColor Yellow
        continue
    }

    $servers[$endpoint.displayName] = @{
        type    = "http"
        url     = "$($endpoint.endpoint)/mcp"
        headers = @{
            "Ocp-Apim-Subscription-Key" = $SubscriptionKey
        }
    }
}

$mcpJson = @{
    servers = $servers
} | ConvertTo-Json -Depth 5

# Write to .vscode/mcp.json
$outputPath = Join-Path $PSScriptRoot ".." ".vscode" "mcp.json"
$outputDir = Split-Path $outputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$mcpJson | Set-Content -Path $outputPath -Encoding utf8
Write-Host "Generated $outputPath" -ForegroundColor Green
Write-Host ""
Write-Host "MCP servers configured:" -ForegroundColor Cyan
foreach ($name in $servers.Keys) {
    Write-Host "  - $name -> $($servers[$name].url)" -ForegroundColor White
}
