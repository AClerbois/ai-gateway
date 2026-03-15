<#
.SYNOPSIS
    Builds and pushes wrapped MCP server Docker images to Azure Container Registry.

.DESCRIPTION
    Reads config/wrapped-mcp-servers.json, builds each Docker image using its
    Dockerfile, and pushes it to the specified ACR. Run this BEFORE deploying
    the Container Apps infrastructure (or after updating a Dockerfile).

.PARAMETER ResourceGroupName
    Name of the Azure resource group containing the ACR.

.PARAMETER AcrName
    Name of the Azure Container Registry (e.g. apimmcpdevacr).
    If not provided, it is derived from the deployment outputs.

.EXAMPLE
    .\build-push-images.ps1 -ResourceGroupName "rg-apim-mcp-dev" -AcrName "apimmcpdevacr"
#>

param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [Parameter()]
    [string]$AcrName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$configPath = Join-Path $repoRoot "config" "wrapped-mcp-servers.json"
$config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

# Resolve ACR name from deployment outputs if not provided
if (-not $AcrName) {
    Write-Host "Resolving ACR name from deployment outputs..." -ForegroundColor Cyan
    $AcrName = az deployment group show `
        --resource-group $ResourceGroupName `
        --name "main" `
        --query "properties.outputs.acrLoginServer.value" `
        --output tsv
    if (-not $AcrName) {
        Write-Error "Could not resolve ACR name. Provide -AcrName parameter."
        return
    }
    # acrLoginServer returns 'myacr.azurecr.io', extract just the name
    $AcrName = $AcrName.Split('.')[0]
    Write-Host "Resolved ACR: $AcrName" -ForegroundColor Green
}

# Login to ACR
Write-Host "`nLogging in to ACR: $AcrName..." -ForegroundColor Cyan
az acr login --name $AcrName
if ($LASTEXITCODE -ne 0) { Write-Error "ACR login failed."; return }

$loginServer = az acr show --name $AcrName --query "loginServer" --output tsv

Write-Host "`nBuilding and pushing images to $loginServer..." -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor DarkGray

foreach ($server in $config.wrappedMcpServers) {
    $imageName = $server.imageName
    $dockerContext = Join-Path $repoRoot $server.dockerContext
    $dockerfile = Join-Path $dockerContext "Dockerfile"
    $fullImageName = "${loginServer}/${imageName}:latest"

    Write-Host "`n[$imageName] Building..." -ForegroundColor Yellow
    
    docker build -t $fullImageName -f $dockerfile $dockerContext
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker build failed for $imageName"
        continue
    }

    Write-Host "[$imageName] Pushing to $loginServer..." -ForegroundColor Yellow
    docker push $fullImageName
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker push failed for $imageName"
        continue
    }

    Write-Host "[$imageName] Done." -ForegroundColor Green
}

Write-Host "`n==========================================" -ForegroundColor DarkGray
Write-Host "All images built and pushed successfully." -ForegroundColor Green
Write-Host "You can now deploy/update the Container Apps infrastructure." -ForegroundColor Cyan
