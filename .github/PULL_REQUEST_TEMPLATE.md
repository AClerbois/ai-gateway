## Description

<!-- Brief description of the changes -->

## Type of Change

- [ ] New MCP server registration
- [ ] New access profile
- [ ] Policy update (primitives filtering, global policies)
- [ ] Configuration update (rate limits, URLs, env vars)
- [ ] Infrastructure change (Bicep)
- [ ] CI/CD pipeline change
- [ ] Documentation update
- [ ] Bug fix

## Config Files Modified

- [ ] `config/mcp-servers.json`
- [ ] `config/profiles.json`
- [ ] `config/wrapped-mcp-servers.json`
- [ ] `config/mcp-whitelist.json`
- [ ] `policies/*.xml`
- [ ] `infra/*.bicep`
- [ ] Other: ___

## Checklist

- [ ] Whitelist validation passes (`scripts/validate-mcp-whitelist.ps1`)
- [ ] Bicep build succeeds (`az bicep build -f infra/main.bicep`)
- [ ] Security review completed (for new servers)
- [ ] Documentation updated (if applicable)
- [ ] Dockerfile added (for new stdio servers)

## Related Issues

<!-- Closes #XX -->
