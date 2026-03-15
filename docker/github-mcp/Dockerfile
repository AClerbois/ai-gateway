# ---------------------------------------------------------------------------
# GitHub MCP Server — stdio → Streamable HTTP via supergateway
# Exposes @modelcontextprotocol/server-github tools through HTTP.
# ---------------------------------------------------------------------------
FROM node:25-slim

RUN npm install -g \
    supergateway@latest \
    @modelcontextprotocol/server-github@latest

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:8000/healthz').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

ENTRYPOINT ["supergateway", \
    "--stdio", "mcp-server-github", \
    "--outputTransport", "streamableHttp", \
    "--port", "8000", \
    "--healthEndpoint", "/healthz"]
