---
name: add-profile
description: "Add a new access profile (APIM Product) to the MCP gateway. Lists available MCP servers from mcp-servers.json, lets the user choose which to include, and updates profiles.json and mcp-whitelist.json allowedProfiles restrictions."
argument-hint: "Describe the profile to create: name, purpose, and which MCP servers to include"
---

# Add Access Profile to APIM Gateway

This skill creates a new access profile (mapped to an APIM Product) that controls which MCP servers a group of consumers can access.

## Procedure

### Step 1 — Gather Profile Information

Ask the user for:
1. **Profile name** (kebab-case, e.g., `data-team`)
2. **Display name** (human-readable, e.g., `Data Team`)
3. **Description** (purpose of this profile)
4. **Subscriptions limit** (max number of subscription keys, default: 10)
5. **Approval required** (boolean — require admin approval for new subscriptions, default: false)

### Step 2 — Show Available MCP Servers

Read `config/mcp-servers.json` and display the available servers:

```
Available MCP Servers:
  1. mslearn-mcp       — Microsoft Learn MCP Server
  2. custom-mcp        — Custom MCP Server
  3. aoai-api          — Azure OpenAI API
  4. github-mcp        — GitHub MCP Server
  5. azuredevops-mcp   — Azure DevOps MCP Server
  6. terraform-mcp     — Terraform MCP Server
  7. snyk-mcp          — Snyk MCP Server
  8. fluentui-blazor-mcp — Fluent UI Blazor MCP Server
```

Ask the user to select servers by number or name. Also offer the option `["*"]` for full access to all servers (including future ones).

### Step 3 — Update config/profiles.json

Add a new entry to the `profiles` array:

```json
{
  "name": "<profile-name>",
  "displayName": "<Display Name>",
  "description": "<description>",
  "servers": ["<server-1>", "<server-2>"],
  "subscriptionsLimit": 10,
  "approvalRequired": false
}
```

### Step 4 — Update Whitelist allowedProfiles

Read `config/mcp-whitelist.json` and for each selected server:
- Check the `restrictions.allowedProfiles` array.
- If it is `["*"]`, no change needed (all profiles are allowed).
- If it lists specific profiles, add the new profile name to the array.

This ensures the whitelist validation passes — a server must explicitly allow the profile or use `["*"]`.

### Step 5 — Run Validation

Execute:
```powershell
pwsh -File scripts/validate-mcp-whitelist.ps1
```

The validation checks that every server referenced in profiles is approved in the whitelist and that profiles are consistent with `allowedProfiles` restrictions.

### Step 6 — Summary

Display:
- Profile name and display name
- Servers included
- Subscriptions limit and approval requirement
- Whitelist restrictions updated
- Remind that the profile creates an APIM Product after deployment

## Reference Files

- `config/profiles.json` — Profile definitions
- `config/mcp-servers.json` — Available MCP server backends
- `config/mcp-whitelist.json` — Whitelist with allowedProfiles restrictions
- `scripts/validate-mcp-whitelist.ps1` — Validation script
- `docs/consumer-guide.md` — Consumer guide with profile descriptions
