# ---------------------------------------------------------------------------
# Fluent UI Blazor MCP Server — stdio → Streamable HTTP via supergateway
# .NET global tool (Microsoft.FluentUI.AspNetCore.McpServer) wrapped with
# supergateway for HTTP transport.
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:9.0-alpine

# Install Node.js for supergateway
RUN apk add --no-cache nodejs npm

# Install FluentUI MCP Server as global .NET tool
RUN dotnet tool install -g Microsoft.FluentUI.AspNetCore.McpServer --prerelease
ENV PATH="${PATH}:/root/.dotnet/tools"

# Install supergateway
RUN npm install -g supergateway@latest

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:8000/healthz').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

ENTRYPOINT ["supergateway", \
    "--stdio", "fluentui-mcp", \
    "--outputTransport", "streamableHttp", \
    "--port", "8000", \
    "--healthEndpoint", "/healthz"]
