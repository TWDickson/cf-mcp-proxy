# cf-mcp-proxy

A generic Cloudflare Worker that proxies authenticated MCP (Model Context Protocol) requests to upstream servers via Cloudflare Access and Tunnel.

## Architecture

```
Claude.ai (OAuth 2.1 + PKCE)
  → CF Worker (OAuth provider + proxy)
    → CF Access validates via SaaS app
    → Worker injects CF Access Service Token headers
    → CF Tunnel → your MCP server
```

## Multi-Environment Deployment

This worker is fully reusable. Deploy multiple instances from one codebase using wrangler environments:

```bash
wrangler deploy --env ha        # → cf-ai.your-subdomain.workers.dev
wrangler deploy --env obsidian  # → cf-obsidian.your-subdomain.workers.dev
```

Add new environments in `wrangler.jsonc`:

```jsonc
"env": {
  "my-service": {
    "name": "cf-my-service",
    "kv_namespaces": [
      { "binding": "OAUTH_KV", "id": "<create via wrangler kv namespace create OAUTH_KV>" }
    ]
  }
}
```

## Setup

### Prerequisites

- Cloudflare account with Workers and Access
- An MCP server accessible via Cloudflare Tunnel
- A CF Access self-hosted app protecting the tunnel hostname
- A CF Access SaaS app as OIDC provider for the Worker

### 1. Create KV Namespace

```bash
wrangler kv namespace create OAUTH_KV --env <env-name>
```

Update the `id` in `wrangler.jsonc` for your environment.

### 2. Set Secrets

```bash
# For each environment:
wrangler secret put MCP_UPSTREAM_URL --env <env-name>
wrangler secret put SERVICE_CLIENT_ID --env <env-name>
wrangler secret put SERVICE_CLIENT_SECRET --env <env-name>
wrangler secret put ACCESS_CLIENT_ID --env <env-name>
wrangler secret put ACCESS_CLIENT_SECRET --env <env-name>
wrangler secret put ACCESS_TOKEN_URL --env <env-name>
wrangler secret put ACCESS_AUTHORIZATION_URL --env <env-name>
wrangler secret put ACCESS_JWKS_URL --env <env-name>
wrangler secret put COOKIE_ENCRYPTION_KEY --env <env-name>
```

Generate `COOKIE_ENCRYPTION_KEY` with: `openssl rand -hex 32`

### 3. Deploy

```bash
npm install
wrangler deploy --env <env-name>
```

### 4. Connect Claude.ai

Add as MCP connector: `https://<worker-name>.your-subdomain.workers.dev/mcp`

## Secrets Reference

| Secret | Description |
|--------|-------------|
| `MCP_UPSTREAM_URL` | Full URL to the upstream MCP server (e.g., `https://service.yourdomain.com/mcp`) |
| `SERVICE_CLIENT_ID` | CF Access Service Token Client ID (injected into upstream requests) |
| `SERVICE_CLIENT_SECRET` | CF Access Service Token Client Secret |
| `ACCESS_CLIENT_ID` | CF Access SaaS app Client ID (OIDC provider) |
| `ACCESS_CLIENT_SECRET` | CF Access SaaS app Client Secret |
| `ACCESS_TOKEN_URL` | CF Access SaaS app Token endpoint |
| `ACCESS_AUTHORIZATION_URL` | CF Access SaaS app Authorization endpoint |
| `ACCESS_JWKS_URL` | CF Access SaaS app JWKS endpoint |
| `COOKIE_ENCRYPTION_KEY` | Random hex string for cookie encryption |

## License

MIT
