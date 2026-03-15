# ---------------------------------------------------------------------------
# Terraform MCP Server — stdio → Streamable HTTP via supergateway
# Exposes terraform-mcp-server tools through HTTP.
# ---------------------------------------------------------------------------
FROM node:25-slim

RUN npm install -g \
    supergateway@latest \
    terraform-mcp-server@latest

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:8000/healthz').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

ENTRYPOINT ["supergateway", \
    "--stdio", "terraform-mcp-server", \
    "--outputTransport", "streamableHttp", \
    "--port", "8000", \
    "--healthEndpoint", "/healthz"]
