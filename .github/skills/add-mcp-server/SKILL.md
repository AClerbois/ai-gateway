---
name: add-mcp-server
description: "Add a new MCP server to the APIM gateway. Supports HTTP (Streamable HTTP), HTTP/SSE, and stdio transports. For stdio servers, analyzes the npm package, creates a Dockerfile with supergateway wrapping, and updates all config files. Handles mcp-servers.json, wrapped-mcp-servers.json, mcp-whitelist.json, and profiles.json."
argument-hint: "Describe the MCP server to add: name, npm package or URL, and transport type (http, sse, stdio)"
---

# Add MCP Server to APIM Gateway

This skill adds a new MCP server backend to the Azure API Management MCP gateway.

## Supported Transport Types

| Transport | Description | Config files updated | Dockerfile |
|-----------|-------------|---------------------|------------|
| `streamable-http` | Server already exposes Streamable HTTP | `mcp-servers.json`, `mcp-whitelist.json` | No |
| `sse` | Server uses legacy SSE transport | `mcp-servers.json`, `mcp-whitelist.json` | No |
| `stdio` | Server uses stdio — requires supergateway wrapping | `mcp-servers.json`, `wrapped-mcp-servers.json`, `mcp-whitelist.json` | Yes |

## Procedure

### Step 1 — Gather Information

Ask the user for:
1. **Server name** (kebab-case, e.g., `my-mcp-server`)
2. **Display name** (human-readable)
3. **Description** (what the server does)
4. **Transport type**: `streamable-http`, `sse`, or `stdio`
5. For HTTP/SSE: **Backend URL** (the remote endpoint)
6. For stdio: **npm package name** (e.g., `@modelcontextprotocol/server-github`)
7. **Rate limit per minute** (default: 60)
8. **Environment variables / secrets** needed (if any)

### Step 2 — For stdio: Analyze the npm Package

If transport is `stdio`:
1. Search for the npm package documentation to find:
   - The CLI command name (e.g., `mcp-server-github` for `@modelcontextprotocol/server-github`)
   - Required environment variables
   - Any special runtime requirements
2. Confirm the CLI command and required env vars with the user.

### Step 3 — For stdio: Create Docker Files

Create `docker/<server-name>/Dockerfile` following this pattern:

```dockerfile
# ---------------------------------------------------------------------------
# <Display Name> - stdio → Streamable HTTP via supergateway
# Exposes <npm-package> tools through HTTP.
# ---------------------------------------------------------------------------
FROM node:20-slim

RUN npm install -g \
    supergateway@latest \
    <npm-package>@latest

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:8000/healthz').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

ENTRYPOINT ["supergateway", \
    "--stdio", "<cli-command>", \
    "--outputTransport", "streamableHttp", \
    "--port", "8000", \
    "--healthEndpoint", "/healthz"]
```

### Step 4 — Update config/mcp-servers.json

Add a new entry to the `mcpServers` array:

```json
{
  "name": "<server-name>",
  "displayName": "<Display Name>",
  "description": "<description>",
  "type": "custom",
  "backendUrl": "https://CONTAINER_APP_FQDN_PLACEHOLDER",
  "transport": "streamable-http",
  "basePath": "<server-name>",
  "rateLimitPerMinute": 60
}
```

- For HTTP/SSE servers, set `backendUrl` to the actual endpoint URL.
- For stdio servers, use `"https://CONTAINER_APP_FQDN_PLACEHOLDER"` (resolved at deploy time).
- Always set `transport` to `"streamable-http"` in mcp-servers.json (even for wrapped stdio — APIM sees it as HTTP after wrapping).
- For Azure OpenAI, add `tokensPerMinute` and `modelDeploymentName` fields, set `type` to `"azure-openai"`.

### Step 5 — For stdio: Update config/wrapped-mcp-servers.json

Add a new entry to the `wrappedMcpServers` array:

```json
{
  "name": "<server-name>",
  "displayName": "<Display Name>",
  "description": "<description>. Wrapped from stdio via supergateway.",
  "imageName": "<server-name>",
  "dockerContext": "docker/<server-name>",
  "envVars": [
    {
      "name": "<ENV_VAR_NAME>",
      "value": ""
    }
  ]
}
```

### Step 6 — Update config/mcp-whitelist.json

Add a new entry to the `approvedServers` array:

```json
{
  "name": "<server-name>",
  "displayName": "<Display Name>",
  "publisher": "<publisher>",
  "source": "<npm-package-or-url>",
  "sourceType": "open-source",
  "transport": "<original-transport>",
  "approvedVersions": ["*"],
  "securityReview": {
    "status": "pending",
    "reviewedBy": "",
    "reviewDate": "<today-YYYY-MM-DD>",
    "nextReviewDate": "",
    "riskLevel": "medium",
    "notes": "Initial registration - security review pending."
  },
  "restrictions": {
    "maxRateLimitPerMinute": 60,
    "allowedProfiles": ["*"],
    "requireEntraAuth": false,
    "requiredSecrets": []
  }
}
```

- Set `sourceType` to `managed-service`, `internal`, `open-source`, or `commercial`.
- Set `transport` to the **original** transport (`stdio`, `sse`, `streamable-http`, or `https`).
- Add `requiredSecrets` with any env var names from the wrapped config.
- Ask the user if they want to restrict to specific profiles via `allowedProfiles`.

### Step 7 — Optionally Add to Profiles

Ask the user: "Should this server be added to any existing profiles?"

Show the current profiles from `config/profiles.json`:
- Read the profiles and display them with their current servers.
- If the user picks profiles, add the server name to each selected profile's `servers` array.
- The `all-mcp-tools` profile with `["*"]` automatically includes all servers.

### Step 8 — Run Validation

Execute the whitelist validation script:
```powershell
pwsh -File scripts/validate-mcp-whitelist.ps1
```

Check for any errors. If the validation fails, fix the configuration issue.

### Step 9 — Summary

Display a summary:
- Server name and transport type
- Config files modified
- Dockerfile created (if stdio)
- Profiles updated
- Whitelist entry status
- Remind user to complete the security review if status is `pending`

## Reference Files

- `config/mcp-servers.json` — Server backend definitions
- `config/wrapped-mcp-servers.json` — stdio servers wrapped with supergateway
- `config/mcp-whitelist.json` — Whitelist registry with security reviews
- `config/mcp-whitelist.schema.json` — JSON Schema for whitelist validation
- `config/profiles.json` — Access profiles with server assignments
- `docker/github-mcp/Dockerfile` — Example Dockerfile pattern for stdio wrapping
- `scripts/validate-mcp-whitelist.ps1` — Whitelist validation script
- `docs/stdio-to-http-guide.md` — Guide for wrapping stdio servers
