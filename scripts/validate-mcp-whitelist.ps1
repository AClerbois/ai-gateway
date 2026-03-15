<#
.SYNOPSIS
    Validates mcp-servers.json against the MCP whitelist registry.

.DESCRIPTION
    Ensures all MCP servers referenced in mcp-servers.json and profiles.json
    are approved in mcp-whitelist.json. Checks:
    - All servers exist in the approved list (not blocked, not missing)
    - Security reviews are not expired
    - Rate limits respect whitelist maximums
    - Profile assignments respect whitelist restrictions

.PARAMETER ConfigPath
    Path to the config directory. Defaults to ./config.

.PARAMETER Environment
    Target environment (dev, staging, prod). Dev may allow relaxed checks
    if policies.allowUnreviewedInDev is true.

.PARAMETER Strict
    If set, treats warnings as errors (non-zero exit code).

.EXAMPLE
    .\scripts\validate-mcp-whitelist.ps1
    .\scripts\validate-mcp-whitelist.ps1 -Environment prod -Strict
#>

param(
    [string]$ConfigPath = "./config",
    [ValidateSet("dev", "staging", "prod")]
    [string]$Environment = "dev",
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

# --- Load files ---
$whitelistFile = Join-Path $ConfigPath "mcp-whitelist.json"
$serversFile = Join-Path $ConfigPath "mcp-servers.json"
$profilesFile = Join-Path $ConfigPath "profiles.json"

if (-not (Test-Path $whitelistFile)) {
    Write-Error "Whitelist registry not found: $whitelistFile"
    exit 1
}
if (-not (Test-Path $serversFile)) {
    Write-Error "MCP servers config not found: $serversFile"
    exit 1
}

$whitelist = Get-Content $whitelistFile -Raw | ConvertFrom-Json
$servers = Get-Content $serversFile -Raw | ConvertFrom-Json
$profiles = if (Test-Path $profilesFile) {
    (Get-Content $profilesFile -Raw | ConvertFrom-Json).profiles
} else {
    @()
}

# --- Build lookup maps ---
$approvedMap = @{}
foreach ($server in $whitelist.approvedServers) {
    $approvedMap[$server.name] = $server
}

$blockedSet = @{}
foreach ($blocked in $whitelist.blockedServers) {
    $blockedSet[$blocked.name] = $blocked
}

$policies = $whitelist.policies
$today = Get-Date -Format "yyyy-MM-dd"
$errors = @()
$warnings = @()

Write-Host ""
Write-Host "=== MCP Whitelist Validation ===" -ForegroundColor Cyan
Write-Host "Environment : $Environment"
Write-Host "Config path : $ConfigPath"
Write-Host "Date        : $today"
Write-Host "Policy      : defaultAction=$($policies.defaultAction)"
Write-Host ""

# --- Check each server in mcp-servers.json ---
foreach ($server in $servers.mcpServers) {
    $name = $server.name
    Write-Host "Checking [$name]..." -NoNewline

    # Check if blocked
    if ($blockedSet.ContainsKey($name)) {
        $reason = $blockedSet[$name].reason
        $errors += "BLOCKED: '$name' is in the blocked list - $reason"
        Write-Host " BLOCKED" -ForegroundColor Red
        continue
    }

    # Check if approved
    if (-not $approvedMap.ContainsKey($name)) {
        if ($policies.defaultAction -eq "deny") {
            if ($policies.allowUnreviewedInDev -and $Environment -eq "dev") {
                $warnings += "UNREVIEWED: '$name' is not in the whitelist (allowed in dev)."
                Write-Host " WARNING (unreviewed, dev only)" -ForegroundColor Yellow
            } else {
                $errors += "DENIED: '$name' is not in the whitelist registry. Add it to mcp-whitelist.json with a security review."
                Write-Host " DENIED" -ForegroundColor Red
            }
        } else {
            $warnings += "UNREGISTERED: '$name' is not in the whitelist (defaultAction=allow)."
            Write-Host " WARNING (unregistered)" -ForegroundColor Yellow
        }
        continue
    }

    $approved = $approvedMap[$name]
    $review = $approved.securityReview
    $restrictions = $approved.restrictions

    # Check security review status
    if ($review.status -eq "rejected") {
        $errors += "REJECTED: '$name' security review status is 'rejected'."
        Write-Host " REJECTED" -ForegroundColor Red
        continue
    }

    if ($review.status -eq "pending") {
        if ($policies.allowUnreviewedInDev -and $Environment -eq "dev") {
            $warnings += "PENDING REVIEW: '$name' review is pending (allowed in dev)."
        } else {
            $errors += "PENDING: '$name' security review is still pending."
        }
    }

    # Check review expiry
    if ($review.nextReviewDate -and $policies.autoBlockOnExpiredReview) {
        if ($review.nextReviewDate -lt $today) {
            if ($Environment -eq "dev" -and $policies.allowUnreviewedInDev) {
                $warnings += "EXPIRED REVIEW: '$name' review expired on $($review.nextReviewDate) (allowed in dev)."
            } else {
                $errors += "EXPIRED: '$name' security review expired on $($review.nextReviewDate). Re-review required."
            }
        } elseif ($policies.notifyOnExpiringSoon) {
            $expiryDate = [datetime]::ParseExact($review.nextReviewDate, "yyyy-MM-dd", $null)
            $daysUntilExpiry = ($expiryDate - (Get-Date)).Days
            if ($daysUntilExpiry -le $policies.notifyOnExpiringSoon) {
                $warnings += "EXPIRING SOON: '$name' review expires in $daysUntilExpiry days ($($review.nextReviewDate))."
            }
        }
    }

    # Check rate limit compliance
    if ($restrictions.maxRateLimitPerMinute -and $server.rateLimitPerMinute) {
        if ($server.rateLimitPerMinute -gt $restrictions.maxRateLimitPerMinute) {
            $errors += "RATE LIMIT: '$name' configured rate ($($server.rateLimitPerMinute)/min) exceeds whitelist maximum ($($restrictions.maxRateLimitPerMinute)/min)."
        }
    }

    # Check token limit compliance (Azure OpenAI)
    if ($restrictions.maxTokensPerMinute -and $server.tokensPerMinute) {
        if ($server.tokensPerMinute -gt $restrictions.maxTokensPerMinute) {
            $errors += "TOKEN LIMIT: '$name' configured tokens ($($server.tokensPerMinute)/min) exceeds whitelist maximum ($($restrictions.maxTokensPerMinute)/min)."
        }
    }

    if ($errors.Count -eq 0 -or $errors[-1] -notmatch [regex]::Escape($name)) {
        Write-Host " OK" -ForegroundColor Green
    }
}

# --- Check profile-to-server assignments ---
Write-Host ""
Write-Host "Checking profile assignments..." -ForegroundColor Cyan

foreach ($profile in $profiles) {
    if ($profile.servers -contains "*") { continue }

    foreach ($serverName in $profile.servers) {
        if ($approvedMap.ContainsKey($serverName)) {
            $restrictions = $approvedMap[$serverName].restrictions
            if ($restrictions.allowedProfiles -and $restrictions.allowedProfiles -notcontains "*") {
                if ($restrictions.allowedProfiles -notcontains $profile.name) {
                    $errors += "PROFILE VIOLATION: Server '$serverName' is not allowed in profile '$($profile.name)'. Allowed: $($restrictions.allowedProfiles -join ', ')."
                }
            }
        }
    }
}

# --- Check MCP Primitives Filter configuration ---
Write-Host ""
Write-Host "Checking MCP primitives filter configuration..." -ForegroundColor Cyan
$validPolicies = @("allowAll", "denyAll", "allowList", "denyList")

foreach ($server in $whitelist.approvedServers) {
    $name = $server.name
    if (-not $server.mcpPrimitives) { continue }

    Write-Host "  Primitives [$name]..." -NoNewline
    $hasError = $false

    foreach ($primitiveType in @("tools", "prompts", "resources")) {
        $filter = $server.mcpPrimitives.$primitiveType
        if (-not $filter) { continue }

        $policy = $filter.policy
        if (-not $policy) {
            $errors += "PRIMITIVES: '$name'.$primitiveType - missing 'policy' field."
            $hasError = $true
            continue
        }

        if ($policy -notin $validPolicies) {
            $errors += "PRIMITIVES: '$name'.$primitiveType - invalid policy '$policy'. Must be one of: $($validPolicies -join ', ')."
            $hasError = $true
            continue
        }

        if ($policy -eq "allowList") {
            if (-not $filter.allowed -or $filter.allowed.Count -eq 0) {
                $errors += "PRIMITIVES: '$name'.$primitiveType - allowList policy requires a non-empty 'allowed' array."
                $hasError = $true
            }
        }
        if ($policy -eq "denyList") {
            if (-not $filter.denied -or $filter.denied.Count -eq 0) {
                $errors += "PRIMITIVES: '$name'.$primitiveType - denyList policy requires a non-empty 'denied' array."
                $hasError = $true
            }
        }

        # Warn if allowAll/denyAll have unnecessary arrays
        if ($policy -eq "allowAll" -or $policy -eq "denyAll") {
            if ($filter.allowed -and $filter.allowed.Count -gt 0) {
                $warnings += "PRIMITIVES: '$name'.$primitiveType - '$policy' policy has 'allowed' array that will be ignored."
            }
            if ($filter.denied -and $filter.denied.Count -gt 0) {
                $warnings += "PRIMITIVES: '$name'.$primitiveType - '$policy' policy has 'denied' array that will be ignored."
            }
        }
    }

    if (-not $hasError) {
        Write-Host " OK" -ForegroundColor Green
    } else {
        Write-Host " ERRORS" -ForegroundColor Red
    }
}

# --- Summary ---
Write-Host ""
Write-Host "=== Validation Summary ===" -ForegroundColor Cyan

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings ($($warnings.Count)):" -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host "  WARNING: $w" -ForegroundColor Yellow
    }
}

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Errors ($($errors.Count)):" -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host "  ERROR: $e" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Validation FAILED." -ForegroundColor Red
    exit 1
}

if ($warnings.Count -gt 0 -and $Strict) {
    Write-Host ""
    Write-Host "Validation FAILED (strict mode - warnings treated as errors)." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Validation PASSED. All $($servers.mcpServers.Count) servers are approved." -ForegroundColor Green
exit 0
