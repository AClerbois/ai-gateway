---
name: update-content
description: "Update MCP gateway configuration content. Modify existing server settings (backend URL, rate limits, description), update whitelist security reviews, change profile server assignments, or update environment variables for wrapped servers. Covers any configuration change not handled by other skills."
argument-hint: "Describe what to update: e.g. change rate limit on github-mcp, update backend URL, renew security review, remove server from profile"
---

# Update MCP Gateway Content

This skill handles updates to existing MCP gateway configuration that don't involve adding new servers, profiles, or policies.

## Common Update Scenarios

| Scenario | Config file(s) |
|----------|----------------|
| Change server backend URL | `mcp-servers.json` |
| Update rate limit | `mcp-servers.json` + `mcp-whitelist.json` |
| Edit server description/display name | `mcp-servers.json`, `mcp-whitelist.json` |
| Renew security review | `mcp-whitelist.json` |
| Add/remove server from profile | `profiles.json`, `mcp-whitelist.json` |
| Update env vars for wrapped server | `wrapped-mcp-servers.json` |
| Change profile subscriptions limit | `profiles.json` |
| Remove a server entirely | All config files + Dockerfile |
| Update whitelist metadata | `mcp-whitelist.json` |

## Procedure

### Step 1 — Identify the Change

Ask the user what they want to update. Read the relevant config file(s) to show the current state.

### Step 2 — Apply the Change

Based on the scenario:

#### Update Server Settings

Read `config/mcp-servers.json`, find the server entry, and modify the requested fields:
- `backendUrl` — new endpoint URL
- `rateLimitPerMinute` — new rate limit
- `displayName`, `description` — text updates
- `tokensPerMinute`, `modelDeploymentName` — for Azure OpenAI servers

If `rateLimitPerMinute` changes, also update `restrictions.maxRateLimitPerMinute` in `config/mcp-whitelist.json` for consistency.

#### Renew Security Review

Update the `securityReview` object in `config/mcp-whitelist.json`:
```json
{
  "status": "approved",
  "reviewedBy": "<reviewer>",
  "reviewDate": "<today-YYYY-MM-DD>",
  "nextReviewDate": "<review+validity-YYYY-MM-DD>",
  "riskLevel": "<low|medium|high|critical>",
  "notes": "<updated notes>"
}
```

#### Add/Remove Server from Profile

Read `config/profiles.json`, find the profile, and modify its `servers` array.
- When adding: also check `mcp-whitelist.json` `allowedProfiles` restrictions.
- When removing: just remove from the `servers` array.

#### Update Wrapped Server Config

Read `config/wrapped-mcp-servers.json`, find the server, and modify:
- `envVars` — add, remove, or update environment variables
- `description`, `displayName` — text updates

#### Remove a Server

This is a multi-file operation:
1. Remove from `config/mcp-servers.json`
2. Remove from `config/wrapped-mcp-servers.json` (if stdio)
3. Remove from `config/mcp-whitelist.json` `approvedServers`
4. Remove from each profile's `servers` array in `config/profiles.json`
5. Optionally delete `docker/<server-name>/` directory
6. Confirm with user before deleting files

### Step 3 — Run Validation

Execute:
```powershell
pwsh -File scripts/validate-mcp-whitelist.ps1
```

### Step 4 — Summary

Display what was changed, which files were modified, and validation results.

## Reference Files

- `config/mcp-servers.json` — Server backend definitions
- `config/wrapped-mcp-servers.json` — stdio server wrapper configs
- `config/mcp-whitelist.json` — Whitelist registry
- `config/profiles.json` — Access profiles
- `config/mcp-whitelist.schema.json` — JSON Schema
- `scripts/validate-mcp-whitelist.ps1` — Validation script
