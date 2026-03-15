# ---------------------------------------------------------------------------
# Fluent UI Blazor MCP Server — stdio → Streamable HTTP via supergateway
# Multi-stage: .NET 9 SDK (dotnet tool) + Node.js (supergateway).
# ---------------------------------------------------------------------------

# Stage 1: Install .NET dotnet tool
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS dotnet-tools
RUN dotnet tool install --global fluentui-mcp --prerelease
ENV PATH="$PATH:/root/.dotnet/tools"

# Stage 2: Final image with Node.js + .NET runtime + supergateway
FROM node:20-slim

# Install .NET 9 runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libicu-dev \
    libssl-dev \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Install .NET 9 runtime
ENV DOTNET_ROOT=/usr/share/dotnet
RUN wget -q https://dot.net/v1/dotnet-install.sh -O dotnet-install.sh \
    && chmod +x dotnet-install.sh \
    && ./dotnet-install.sh --channel 9.0 --runtime dotnet --install-dir $DOTNET_ROOT \
    && rm dotnet-install.sh \
    && ln -s $DOTNET_ROOT/dotnet /usr/bin/dotnet
ENV PATH="$PATH:$DOTNET_ROOT:/root/.dotnet/tools"

# Copy dotnet tool from build stage
COPY --from=dotnet-tools /root/.dotnet/tools /root/.dotnet/tools

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
