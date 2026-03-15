# ---------------------------------------------------------------------------
# Script: setup-mcp-servers.ps1
# Creates native MCP-type APIs in Azure APIM for each eligible MCP server.
# Uses the Azure APIM preview API (2024-06-01-preview) which supports
# type='mcp' with mcpProperties for native MCP protocol handling.
# ---------------------------------------------------------------------------

param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot/../config/mcp-servers.json",

    [Parameter(Mandatory = $false)]
    [string]$ProfilesPath = "$PSScriptRoot/../config/profiles.json",

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroup = "",

    [Parameter(Mandatory = $false)]
    [string]$ApimName = ""
)

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Auto-discover APIM instance if not provided
# ---------------------------------------------------------------------------
if (-not $ResourceGroup -or -not $ApimName) {
    Write-Host "Auto-discovering APIM instance..." -ForegroundColor Cyan
    $apimInstances = az apim list --query "[?tags.project=='apim-mcp']" -o json 2>$null | ConvertFrom-Json
    if ($apimInstances -and $apimInstances.Count -gt 0) {
        $apimInstance = $apimInstances[0]
        $ResourceGroup = $apimInstance.resourceGroup
        $ApimName = $apimInstance.name
        Write-Host "  Found: $ApimName in $ResourceGroup" -ForegroundColor Green
    }
    else {
        Write-Error "No APIM instance found with tag project=apim-mcp. Specify -ResourceGroup and -ApimName."
        exit 1
    }
}

$apiVersion = "2024-06-01-preview"
$apimResourceId = "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"

# ---------------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------------
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$profilesConfig = Get-Content $ProfilesPath -Raw | ConvertFrom-Json

# ---------------------------------------------------------------------------
# Determine eligible MCP servers (exclude Azure OpenAI and placeholders)
# ---------------------------------------------------------------------------
$eligibleServers = $config.mcpServers | Where-Object {
    $_.transport -eq "streamable-http" -and
    $_.type -ne "azure-openai" -and
    $_.backendUrl -notlike "*PLACEHOLDER*"
}

Write-Host "`nEligible MCP servers for native registration:" -ForegroundColor Cyan
$eligibleServers | ForEach-Object { Write-Host "  - $($_.name) ($($_.backendUrl))" }

# ---------------------------------------------------------------------------
# Helper: Compute MCP backend URL (strip trailing /mcp for correct routing)
# ---------------------------------------------------------------------------
function Get-McpBackendUrl {
    param([string]$OriginalUrl)
    # MCP-type APIs append /mcp to the backend URL during routing.
    # If the original backend URL already ends with /mcp, strip it to avoid doubling.
    if ($OriginalUrl -match '/mcp/?$') {
        return $OriginalUrl -replace '/mcp/?$', ''
    }
    return $OriginalUrl
}

# ---------------------------------------------------------------------------
# Helper: Write JSON body to temp file and call az rest (avoids CLI escaping issues)
# ---------------------------------------------------------------------------
function Invoke-AzRest {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Body
    )
    $tempFile = [System.IO.Path]::GetTempFileName()
    try {
        $Body | ConvertTo-Json -Depth 10 | Set-Content -Path $tempFile -Encoding utf8
        $result = az rest --method $Method --uri $Uri --body "@$tempFile" --output none 2>&1
        return $LASTEXITCODE
    }
    finally {
        Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Create native MCP servers
# ---------------------------------------------------------------------------
$created = @()

foreach ($server in $eligibleServers) {
    $mcpApiName = "$($server.name)-mcp-server"
    $mcpBackendUrl = Get-McpBackendUrl -OriginalUrl $server.backendUrl
    $existingBackendName = "$($server.name)-backend"

    Write-Host "`n--- $($server.displayName) ---" -ForegroundColor Yellow

    # Check if a dedicated MCP backend is needed (URL differs from existing backend)
    $needsNewBackend = $mcpBackendUrl -ne $server.backendUrl
    $backendName = $existingBackendName

    if ($needsNewBackend) {
        $backendName = "$($server.name)-mcp-backend"
        Write-Host "  Creating MCP backend: $backendName ($mcpBackendUrl)" -ForegroundColor Cyan

        $backendBody = @{
            properties = @{
                title       = "$($server.displayName) (MCP)"
                description = "MCP-native backend for $($server.displayName)"
                url         = $mcpBackendUrl
                protocol    = "http"
                tls         = @{
                    validateCertificateChain = $true
                    validateCertificateName  = $true
                }
            }
        }

        $backendUri = "${apimResourceId}/backends/${backendName}?api-version=${apiVersion}"
        $exitCode = Invoke-AzRest -Method PUT -Uri $backendUri -Body $backendBody
        if ($exitCode -ne 0) {
            Write-Warning "  Failed to create backend $backendName — skipping server"
            continue
        }
        Write-Host "  Backend created." -ForegroundColor Green
    }
    else {
        Write-Host "  Using existing backend: $backendName" -ForegroundColor Gray
    }

    # Create MCP-type API
    Write-Host "  Creating MCP API: $mcpApiName" -ForegroundColor Cyan

    $apiBody = @{
        properties = @{
            displayName        = "$($server.displayName) (MCP)"
            description        = "$($server.description) (Native MCP Server)"
            type               = "mcp"
            path               = "$($server.basePath)-mcp-server"
            protocols          = @("https")
            subscriptionRequired = $true
            subscriptionKeyParameterNames = @{
                header = "Ocp-Apim-Subscription-Key"
                query  = "subscription-key"
            }
            backendId          = $backendName
            isCurrent          = $true
            mcpProperties      = @{
                transportType = "streamable"
            }
        }
    }

    $apiUri = "${apimResourceId}/apis/${mcpApiName}?api-version=${apiVersion}"
    $exitCode = Invoke-AzRest -Method PUT -Uri $apiUri -Body $apiBody
    if ($exitCode -ne 0) {
        Write-Warning "  Failed to create API $mcpApiName"
        continue
    }
    Write-Host "  MCP API created." -ForegroundColor Green

    $created += $mcpApiName
}

# ---------------------------------------------------------------------------
# Associate MCP APIs to products (profiles)
# ---------------------------------------------------------------------------
Write-Host "`n--- Associating MCP APIs to products ---" -ForegroundColor Yellow

$allServerNames = $config.mcpServers | ForEach-Object { $_.name }

foreach ($profile in $profilesConfig.profiles) {
    $profileServers = $profile.servers
    if ($profileServers -contains "*") {
        $profileServers = $allServerNames
    }

    foreach ($serverName in $profileServers) {
        $mcpApiName = "$serverName-mcp-server"
        if ($created -contains $mcpApiName) {
            Write-Host "  Adding $mcpApiName to product $($profile.name)" -ForegroundColor Cyan
            $assocUri = "${apimResourceId}/products/$($profile.name)/apis/${mcpApiName}?api-version=${apiVersion}"
            $exitCode = Invoke-AzRest -Method PUT -Uri $assocUri -Body @{}
            if ($exitCode -ne 0) {
                Write-Warning "  Failed to associate $mcpApiName to $($profile.name)"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host "Created $($created.Count) native MCP servers:" -ForegroundColor Green
$created | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }

Write-Host "`nMCP Server endpoints:" -ForegroundColor Cyan
$gatewayUrl = (az apim show -n $ApimName -g $ResourceGroup --query gatewayUrl -o tsv 2>$null)
foreach ($server in $eligibleServers) {
    $mcpApiName = "$($server.name)-mcp-server"
    if ($created -contains $mcpApiName) {
        Write-Host "  $($server.name): ${gatewayUrl}/$($server.basePath)-mcp-server/mcp" -ForegroundColor White
    }
}

Write-Host "`nDone! Native MCP servers are now visible in the APIM 'MCP Servers' blade." -ForegroundColor Green
