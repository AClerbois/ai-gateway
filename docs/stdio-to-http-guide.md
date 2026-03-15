# Guide : Exposer des serveurs MCP stdio via l'APIM Gateway

Ce guide explique comment transformer des serveurs MCP utilisant le transport **stdio** en endpoints **Streamable HTTP**, les déployer sur **Azure Container Apps**, et les exposer de manière sécurisée à travers **Azure API Management**.

## Architecture

```
                        ┌──────────────────────────────────────┐
MCP Client (VS Code)    │         Azure API Management          │
       │                │  ┌──────────────────────────────────┐ │
       │ HTTPS           │  │  Subscription Key + Rate Limit   │ │
       ├───────────────►│  │  + Logging + Optional OAuth       │ │
       │                │  └───────────────┬──────────────────┘ │
       │                └─────────────────┼────────────────────┘
                                          │
                        ┌─────────────────▼────────────────────┐
                        │    Azure Container Apps Environment    │
                        │                                        │
                        │  ┌────────────┐  ┌────────────┐       │
                        │  │ github-mcp │  │ snyk-mcp   │       │
                        │  │ Container  │  │ Container  │       │
                        │  └─────┬──────┘  └─────┬──────┘       │
                        │       ...              ...             │
                        │  ┌────────────────────────────┐       │
                        │  │  Chaque conteneur exécute : │       │
                        │  │  supergateway               │       │
                        │  │    --stdio "mcp-server-xxx"  │       │
                        │  │    --outputTransport          │       │
                        │  │        streamableHttp         │       │
                        │  │    --port 8000                │       │
                        │  └────────────────────────────┘       │
                        └────────────────────────────────────────┘
```

## Concept

Les serveurs MCP comme **GitHub**, **Azure DevOps**, **Terraform**, **Snyk** et **Fluent UI Blazor** utilisent le transport **stdio** (entrée/sortie standard). Or, Azure API Management ne peut proxifier que des backends **HTTP/HTTPS**.

La solution utilise **[supergateway](https://github.com/supercorp-ai/supergateway)** (npm package) pour convertir le transport :

```
stdio MCP Server  →  supergateway  →  Streamable HTTP (:8000/mcp)  →  APIM
```

## Serveurs MCP wrappés

| Serveur | Package | Nécessite des secrets |
|---------|---------|----------------------|
| GitHub MCP | `@modelcontextprotocol/server-github` | `GITHUB_PERSONAL_ACCESS_TOKEN` |
| Azure DevOps MCP | `@anthropic/azure-devops-mcp-server` | `AZURE_DEVOPS_PAT`, `AZURE_DEVOPS_ORG_URL` |
| Terraform MCP | `@anthropic/terraform-mcp-server` | Non |
| Snyk MCP | `@anthropic/snyk-mcp-server` | `SNYK_TOKEN` |
| Fluent UI Blazor MCP | `fluentui-mcp` (dotnet tool) | Non |

## Prérequis

- Docker Desktop installé et fonctionnel
- Azure CLI (`az`) avec l'extension Container Apps
- Un Azure Container Registry (ACR) déployé (via le Bicep fourni)
- Les tokens/secrets nécessaires pour chaque serveur MCP

## Étapes de déploiement

### 1. Configurer les secrets

Éditez `config/wrapped-mcp-servers.json` et renseignez les valeurs des variables d'environnement :

```json
{
  "name": "GITHUB_PERSONAL_ACCESS_TOKEN",
  "value": "ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
}
```

> **Sécurité** : Ne commitez jamais de secrets dans le dépôt. En production, utilisez Azure Key Vault avec des références de secrets Container Apps.

### 2. Déployer l'infrastructure de base

Si ce n'est pas déjà fait, déployez l'infrastructure complète (APIM + ACR + Container Apps Environment) :

```bash
az group create --name rg-apim-mcp-dev --location westeurope

az deployment group create \
  --resource-group rg-apim-mcp-dev \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

### 3. Build et push des images Docker

```powershell
.\scripts\build-push-images.ps1 `
  -ResourceGroupName "rg-apim-mcp-dev" `
  -AcrName "apimmcpdevacr"
```

Ce script :
1. Se connecte à l'ACR
2. Build chaque Dockerfile depuis `docker/<server-name>/`
3. Push l'image vers l'ACR avec le tag `latest`

### 4. Redéployer les Container Apps

Après le push des images, redéployez pour que Container Apps tire les nouvelles images :

```bash
az deployment group create \
  --resource-group rg-apim-mcp-dev \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

### 5. Mettre à jour les backends APIM

Les URLs de backend dans `config/mcp-servers.json` utilisent un placeholder (`CONTAINER_APP_FQDN_PLACEHOLDER`). Après déploiement, récupérez les FQDNs :

```bash
az deployment group show \
  --resource-group rg-apim-mcp-dev \
  --name main \
  --query "properties.outputs.containerAppFqdns.value" \
  --output table
```

Mettez à jour les `backendUrl` dans `config/mcp-servers.json` avec les vrais FQDNs, puis redéployez.

### 6. Générer la config VS Code

```powershell
.\scripts\generate-mcp-config.ps1 `
  -ResourceGroupName "rg-apim-mcp-dev" `
  -DeploymentName "main" `
  -SubscriptionKey "<votre-clé>"
```

## Ajouter un nouveau serveur MCP stdio

Pour ajouter un nouveau serveur MCP stdio au gateway :

### 1. Créer le Dockerfile

Créez `docker/<server-name>/Dockerfile` :

```dockerfile
FROM node:20-slim

RUN npm install -g \
    supergateway@latest \
    <package-npm-du-serveur>@latest

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD node -e "fetch('http://localhost:8000/healthz').then(r => r.ok ? process.exit(0) : process.exit(1)).catch(() => process.exit(1))"

ENTRYPOINT ["supergateway", \
    "--stdio", "<commande-du-serveur>", \
    "--outputTransport", "streamableHttp", \
    "--port", "8000", \
    "--healthEndpoint", "/healthz"]
```

Pour les serveurs .NET (`dotnet tool`), utilisez le pattern multi-stage du Dockerfile Fluent UI Blazor.

### 2. Ajouter la config

Ajoutez une entrée dans `config/wrapped-mcp-servers.json` :

```json
{
  "name": "mon-serveur-mcp",
  "displayName": "Mon Serveur MCP",
  "description": "Description du serveur.",
  "imageName": "mon-serveur-mcp",
  "dockerContext": "docker/mon-serveur-mcp",
  "envVars": [
    {
      "name": "MA_VARIABLE_SECRETE",
      "value": ""
    }
  ]
}
```

Et dans `config/mcp-servers.json` (pour l'enregistrement APIM) :

```json
{
  "name": "mon-serveur-mcp",
  "displayName": "Mon Serveur MCP",
  "description": "Mon serveur MCP via supergateway (stdio → Streamable HTTP).",
  "type": "custom",
  "backendUrl": "https://<CONTAINER_APP_FQDN>",
  "transport": "streamable-http",
  "basePath": "mon-serveur-mcp",
  "rateLimitPerMinute": 60
}
```

### 3. Build, push, et redéployer

```powershell
# Build et push
.\scripts\build-push-images.ps1 -ResourceGroupName "rg-apim-mcp-dev" -AcrName "apimmcpdevacr"

# Redéployer
az deployment group create \
  --resource-group rg-apim-mcp-dev \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

## Tester localement

Vous pouvez tester un serveur wrappé localement avant de le déployer :

```bash
# Build l'image
docker build -t github-mcp-test docker/github-mcp/

# Lancer avec un token GitHub
docker run -it --rm -p 8000:8000 \
  -e GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxxx \
  github-mcp-test

# Tester l'endpoint de santé
curl http://localhost:8000/healthz

# Tester le MCP (JSON-RPC initialize)
curl -X POST http://localhost:8000/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}'
```

## Dépannage

| Problème | Cause probable | Solution |
|----------|---------------|----------|
| Container App ne démarre pas | Image non trouvée dans ACR | Vérifiez que `build-push-images.ps1` a réussi |
| Health check échoue | Le serveur MCP met du temps à démarrer | Augmentez `--start-period` dans le `HEALTHCHECK` |
| `401 Unauthorized` via APIM | Clé de souscription manquante | Ajoutez `Ocp-Apim-Subscription-Key` dans les headers |
| Erreur MCP `GITHUB_PERSONAL_ACCESS_TOKEN not set` | Variable d'env manquante | Configurez la valeur dans `wrapped-mcp-servers.json` |
| `429 Too Many Requests` | Rate limit atteint | Ajustez `rateLimitPerMinute` dans `mcp-servers.json` |

## Sécurité en production

- **Ne stockez jamais de secrets en clair** dans les fichiers de config. Utilisez Azure Key Vault.
- Activez la **validation Entra ID** (décommentez dans `mcp-passthrough-policy.xml`).
- Utilisez un ACR avec un **SKU Standard ou Premium** et désactivez `adminUserEnabled`.
- Activez les **managed identities** pour Container Apps → ACR (au lieu de admin credentials).
- Configurez des **virtual network** pour isoler Container Apps et APIM.
