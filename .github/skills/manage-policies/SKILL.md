---
name: manage-policies
description: "Manage MCP gateway governance policies. Configure MCP primitives filtering (tools, prompts, resources) per server with allowAll/denyAll/allowList/denyList rules. Update global policies like defaultAction, requireSecurityReview, and mcpPrimitivesDefaults in mcp-whitelist.json."
argument-hint: "Describe the policy change: e.g. block delete tools on github-mcp, set default deny for prompts, require security review"
---

# Manage MCP Gateway Policies

This skill manages governance policies for the APIM MCP gateway, including MCP primitives filtering and global registry policies.

## Policy Types

### 1. MCP Primitives Filtering (per server)

Controls which MCP tools, prompts, and resources are allowed/blocked for a specific server.

| Policy | Effect |
|--------|--------|
| `allowAll` | No filtering — all primitives pass through |
| `denyAll` | Block all primitives of this type |
| `allowList` | Only listed primitive names are allowed |
| `denyList` | Listed primitive names are blocked, rest allowed |

Wildcards supported: `delete_*` matches `delete_repository`, `delete_branch`, etc.

### 2. Global Policies (registry-level)

| Policy | Type | Description |
|--------|------|-------------|
| `defaultAction` | `deny` or `allow` | Action for unlisted servers |
| `requireSecurityReview` | boolean | Require security review before approval |
| `maxReviewValidityDays` | integer | Max days before review expires |
| `autoBlockOnExpiredReview` | boolean | Auto-block expired reviews |
| `allowUnreviewedInDev` | boolean | Skip review in dev environments |
| `notifyOnExpiringSoon` | integer | Days before expiry to warn |
| `mcpPrimitivesDefaults` | object | Default primitive filters for servers without explicit config |

## Procedure

### Step 1 — Identify the Policy Change

Ask the user what they want to do:
- **A)** Configure primitives filtering for a specific server
- **B)** Update global policies
- **C)** Set default primitives filtering policy

### For Option A: Server Primitives Filtering

#### Step A.1 — Select Server

Read `config/mcp-whitelist.json` and display approved servers with their current primitives configuration (if any):

```
Approved servers:
  1. mslearn-mcp       — No primitives config (defaults apply)
  2. github-mcp        — tools: denyList [delete_repository, delete_branch, delete_file]
  3. azuredevops-mcp   — tools: allowList [9 items], resources: denyList [secret://*]
  ...
```

#### Step A.2 — Select Primitive Type

Ask which primitive type to configure: `tools`, `prompts`, or `resources`.

#### Step A.3 — Select Policy

Ask which policy to apply: `allowAll`, `denyAll`, `allowList`, or `denyList`.

#### Step A.4 — Provide Names (for allowList/denyList)

If `allowList`: ask for the list of allowed primitive names.
If `denyList`: ask for the list of denied primitive names.
Remind the user that wildcards like `delete_*` and `secret://*` are supported.
Optionally ask for a `reason` string explaining the policy.

#### Step A.5 — Update mcp-whitelist.json

Add or modify the `mcpPrimitives` object on the target server in `approvedServers`:

```json
{
  "name": "github-mcp",
  "mcpPrimitives": {
    "tools": {
      "policy": "denyList",
      "denied": ["delete_repository", "delete_branch", "delete_file"],
      "reason": "Destructive operations blocked in production"
    },
    "prompts": {
      "policy": "allowAll"
    },
    "resources": {
      "policy": "allowAll"
    }
  }
}
```

### For Option B: Global Policies

#### Step B.1 — Show Current Policies

Read and display the current `policies` section from `config/mcp-whitelist.json`.

#### Step B.2 — Select Policy to Update

Ask which policy field to modify and the new value.

#### Step B.3 — Update mcp-whitelist.json

Modify the `policies` section in `config/mcp-whitelist.json`.

### For Option C: Default Primitives Filtering

#### Step C.1 — Configure mcpPrimitivesDefaults

This sets the default filtering applied to all servers that don't have explicit `mcpPrimitives`.

Follow the same pattern as Option A (steps A.2-A.4) but update `policies.mcpPrimitivesDefaults` instead of a specific server.

### Step 2 — Run Validation

Execute:
```powershell
pwsh -File scripts/validate-mcp-whitelist.ps1
```

The validation checks:
- Policy values are valid enum values (`allowAll`, `denyAll`, `allowList`, `denyList`)
- `allowList` policies have an `allowed` array
- `denyList` policies have a `denied` array
- Warns on unnecessary arrays (e.g., `allowed` with `denyAll`)

### Step 3 — Summary

Display the changes made and validation results.

## Reference Files

- `config/mcp-whitelist.json` — Whitelist registry with policies and primitives
- `config/mcp-whitelist.schema.json` — JSON Schema for validation
- `policies/mcp-passthrough-policy.xml` — APIM policy implementing runtime filtering
- `policies/mcp-primitives-filter.xml` — Standalone primitives filter reference
- `scripts/validate-mcp-whitelist.ps1` — Validation script
- `docs/consumer-guide.md` — Consumer guide with primitives filtering documentation
