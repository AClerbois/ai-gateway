# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| main    | Yes       |

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do NOT open a public issue** for security vulnerabilities.
2. Send details to **adrien@senseof.tech** with the subject `[SECURITY] ai-gateway vulnerability report`.
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Affected component (APIM policy, Bicep, config, etc.)
   - Potential impact

You will receive an acknowledgment within **48 hours** and a detailed response within **5 business days**.

## Security Practices

This project implements several security controls:

- **MCP Whitelist Registry** — Only approved servers can be deployed (`config/mcp-whitelist.json`)
- **Security Reviews** — Mandatory review process with expiration tracking
- **MCP Primitives Filtering** — Granular control over tools, prompts, and resources per server
- **APIM Policies** — Rate limiting, token limits, Entra ID authentication
- **OIDC Authentication** — GitHub Actions uses workload identity federation (no stored secrets)
- **CI/CD Validation** — Automated whitelist validation before deployment
