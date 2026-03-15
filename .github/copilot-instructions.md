# Copilot Instructions - APIM MCP Gateway

This repository manages an Azure API Management (APIM) gateway for MCP (Model Context Protocol) servers.

## Project Structure

- `config/` — JSON configuration files (source of truth for all servers, profiles, and governance)
- `docker/` — Dockerfiles for wrapping stdio MCP servers via supergateway
- `infra/` — Bicep infrastructure as code
- `policies/` — APIM XML policy files
- `scripts/` — PowerShell automation scripts
- `docs/` — Documentation (French)
- `.github/skills/` — VS Code skills for guided workflows

## Configuration Files

| File | Purpose |
|------|---------|
| `config/mcp-servers.json` | Server backends: name, URL, transport, rate limits |
| `config/profiles.json` | Access profiles with server assignments |
| `config/wrapped-mcp-servers.json` | stdio servers wrapped with supergateway + Container Apps |
| `config/mcp-whitelist.json` | Governance: approvals, security reviews, primitives filtering |
| `config/mcp-whitelist.schema.json` | JSON Schema for whitelist validation |

## Processing Issues

When assigned to an issue, follow the matching skill in `.github/skills/`:

### Issue labeled `mcp-server` → Use `add-mcp-server` skill

1. Parse the **Server Information** table from the issue body to extract: server name, display name, description, transport, backend URL or npm package, publisher, source type.
2. Parse the **Environment Variables** table for any required env vars.
3. Parse **Rate Limits** for `rateLimitPerMinute` and optional `tokensPerMinute`.
4. Parse **Profile Assignment** checkboxes to determine which profiles to add the server to.
5. Follow the `add-mcp-server` skill procedure:
   - Add entry to `config/mcp-servers.json`
   - For stdio: create `docker/<name>/Dockerfile` and add to `config/wrapped-mcp-servers.json`
   - Add whitelist entry to `config/mcp-whitelist.json` with `securityReview.status: "pending"`
   - Add to selected profiles in `config/profiles.json`
6. Run validation: `pwsh -File scripts/validate-mcp-whitelist.ps1`
7. Commit with message: `feat: add <server-name> MCP server (closes #<issue>)`

### Issue labeled `profile` → Use `add-profile` skill

1. Parse the **Profile Information** table: name, display name, description, subscriptions limit, approval required.
2. Parse **Server Selection** checkboxes to determine included servers.
3. Follow the `add-profile` skill procedure:
   - Add profile to `config/profiles.json`
   - Update `allowedProfiles` in `config/mcp-whitelist.json` for each selected server
4. Run validation: `pwsh -File scripts/validate-mcp-whitelist.ps1`
5. Commit with message: `feat: add <profile-name> profile (closes #<issue>)`

## Parsing Issue Body

Issue templates use markdown tables with this format:
```
| **Field Name** | value |
```

Extract values by:
- Reading between the `|` delimiters in each row
- Stripping markdown bold (`**`) from field names
- Stripping backticks from values
- Treating empty cells as no value provided

Checkboxes use `- [x]` for checked and `- [ ]` for unchecked.

## Validation Rules

- Server names must be kebab-case and unique across all config files
- All JSON files must remain valid after edits
- Always run `pwsh -File scripts/validate-mcp-whitelist.ps1` after changes
- Bicep can be validated with `az bicep build -f infra/main.bicep`

## Dockerfile Pattern (for stdio servers)

```dockerfile
FROM node:20-slim
RUN npm install -g supergateway@latest <npm-package>@latest
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:8000/healthz').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"
ENTRYPOINT ["supergateway", "--stdio", "<cli-command>", "--outputTransport", "streamableHttp", "--port", "8000", "--healthEndpoint", "/healthz"]
```
