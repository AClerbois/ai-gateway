<#
.SYNOPSIS
    Generates MCP Registry v0.1 JSON files from the whitelist, per profile.

.DESCRIPTION
    Reads mcp-whitelist.json, mcp-servers.json, and profiles.json to produce
    MCP Registry v0.1-compliant JSON files compatible with GitHub Copilot
    MCP Allowlist. Each profile generates its own registry output so that
    organizations can point different teams to different registries.

    Output structure:
      output/
        registry/
          all-mcp-tools/servers.json
          developer/servers.json
          business-analyst/servers.json
          app-1/servers.json
          app-2/servers.json

    Each servers.json follows the MCP Registry v0.1 spec:
    https://registry.modelcontextprotocol.io/docs

.PARAMETER ConfigPath
    Path to the config directory containing whitelist, servers, and profiles.

.PARAMETER OutputPath
    Path where registry files will be generated.

.PARAMETER ApimGatewayUrl
    Base URL of the APIM gateway (e.g. https://apim-mcp-dev.azure-api.net).

.EXAMPLE
    .\scripts\generate-mcp-registry.ps1 -ApimGatewayUrl "https://apim-mcp-dev.azure-api.net"
#>

param(
    [string]$ConfigPath = "./config",
    [string]$OutputPath = "./output/registry",
    [Parameter(Mandatory = $true)]
    [string]$ApimGatewayUrl
)

$ErrorActionPreference = "Stop"

# --- Load configuration files ---
$whitelist = Get-Content (Join-Path $ConfigPath "mcp-whitelist.json") -Raw | ConvertFrom-Json
$servers = (Get-Content (Join-Path $ConfigPath "mcp-servers.json") -Raw | ConvertFrom-Json).mcpServers
$profiles = (Get-Content (Join-Path $ConfigPath "profiles.json") -Raw | ConvertFrom-Json).profiles

# --- Build lookup maps ---
$approvedMap = @{}
foreach ($s in $whitelist.approvedServers) {
    $approvedMap[$s.name] = $s
}

$serverMap = @{}
foreach ($s in $servers) {
    $serverMap[$s.name] = $s
}

$blockedNames = @()
if ($whitelist.blockedServers) {
    $blockedNames = $whitelist.blockedServers | ForEach-Object { $_.name }
}

# --- Generate registry per profile ---
$generatedCount = 0

foreach ($profile in $profiles) {
    $profileName = $profile.name
    $profileDir = Join-Path $OutputPath $profileName

    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    # Resolve server list for this profile
    if ($profile.servers -contains "*") {
        $profileServerNames = $servers | ForEach-Object { $_.name }
    }
    else {
        $profileServerNames = $profile.servers
    }

    # Filter: only approved, non-blocked servers
    $registryServers = @()

    foreach ($name in $profileServerNames) {
        if ($name -in $blockedNames) {
            Write-Warning "[$profileName] Skipping blocked server: $name"
            continue
        }
        if (-not $approvedMap.ContainsKey($name)) {
            Write-Warning "[$profileName] Skipping server not in whitelist: $name"
            continue
        }

        $approved = $approvedMap[$name]
        if ($approved.securityReview.status -ne "approved") {
            Write-Warning "[$profileName] Skipping server with review status '$($approved.securityReview.status)': $name"
            continue
        }

        $serverDef = $serverMap[$name]
        if (-not $serverDef) {
            Write-Warning "[$profileName] Server '$name' is in whitelist but not in mcp-servers.json — skipping."
            continue
        }

        # Build MCP Registry v0.1 server entry
        $endpointUrl = "$ApimGatewayUrl/$($serverDef.basePath)"

        $registryEntry = [ordered]@{
            id          = $name
            name        = $name
            description = $serverDef.description
            publisher   = @{
                name = $approved.publisher
            }
            repository  = @{
                url = if ($approved.source -match "^https?://") { $approved.source } else { "" }
            }
            version_detail = @{
                version   = "1.0.0"
                release_date = $approved.securityReview.reviewDate
            }
            packages    = @(
                [ordered]@{
                    registry_name = "apim-mcp-gateway"
                    name          = $name
                    version       = "1.0.0"
                    environment_variables = @()
                    arguments             = @()
                }
            )
            remotes     = @(
                [ordered]@{
                    transport_type = "streamable-http"
                    url            = $endpointUrl
                }
            )
        }

        $registryServers += $registryEntry
    }

    # Build the v0.1 servers list response
    $registryOutput = [ordered]@{
        servers = $registryServers
        metadata = [ordered]@{
            profile     = $profileName
            displayName = $profile.displayName
            description = $profile.description
            generated   = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
            source      = "apim-mcp-whitelist"
            gatewayUrl  = $ApimGatewayUrl
        }
    }

    $outFile = Join-Path $profileDir "servers.json"
    $registryOutput | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding utf8

    # Also generate individual server version files
    foreach ($entry in $registryServers) {
        $serverDir = Join-Path $profileDir "servers" $entry.id "versions"
        if (-not (Test-Path $serverDir)) {
            New-Item -ItemType Directory -Path $serverDir -Force | Out-Null
        }

        # latest.json
        $entry | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $serverDir "latest.json") -Encoding utf8
        # 1.0.0.json
        $entry | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $serverDir "1.0.0.json") -Encoding utf8
    }

    $generatedCount++
    Write-Host "[OK] Profile '$profileName': $($registryServers.Count) servers -> $outFile"
}

# --- Summary ---
Write-Host ""
Write-Host "=== MCP Registry Generation Complete ==="
Write-Host "Profiles generated: $generatedCount"
Write-Host "Output directory:   $OutputPath"
Write-Host ""
Write-Host "To configure GitHub Copilot MCP Allowlist:"
Write-Host "  1. Host the registry files (e.g. via Azure API Center or static hosting)"
Write-Host "  2. Set MCP Registry URL in GitHub org settings > Copilot > Policies"
Write-Host "  3. Set policy to 'Registry only' to enforce allowlist"
