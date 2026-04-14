#!/usr/bin/env bash
# deploy.sh — Deploy a cf-mcp-proxy environment and register its callback URI
#
# Usage: ./deploy.sh <env>
#   e.g. ./deploy.sh ynab
#
# Requires:
#   CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN in environment or .env file
#   SAAS_APP_ID — the CF Access SaaS app ("MCP OAuth Provider") application ID

set -euo pipefail

ENV="${1:-}"
if [[ -z "$ENV" ]]; then
  echo "Usage: $0 <env>" >&2
  exit 1
fi

# Load .env if present
if [[ -f .env ]]; then
  set -a; source .env; set +a
fi

: "${CLOUDFLARE_ACCOUNT_ID:?CLOUDFLARE_ACCOUNT_ID must be set}"
: "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN must be set}"

# MCP OAuth Provider SaaS app ID (shared across all environments)
SAAS_APP_ID="${SAAS_APP_ID:-a202cdb6-6ef6-4583-9880-737f5fb31e6c}"

# Deploy the worker
echo "→ Deploying cf-mcp-proxy env: $ENV"
npx wrangler deploy --env "$ENV"

# Derive the worker name from wrangler.jsonc
WORKER_NAME=$(node -e "
  const fs = require('fs');
  const src = fs.readFileSync('wrangler.jsonc', 'utf8').replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/.*/g, '');
  const cfg = JSON.parse(src);
  console.log(cfg.env['$ENV'].name);
")

CALLBACK_URL="https://${WORKER_NAME}.twdickson.workers.dev/callback"
echo "→ Registering callback URI: $CALLBACK_URL"

# Fetch current redirect_uris
CURRENT=$(curl -sf \
  "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/access/apps/${SAAS_APP_ID}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  | node -e "
    let d=''; process.stdin.on('data',c=>d+=c).on('end',()=>{
      const uris = JSON.parse(d).result.saas_app.redirect_uris;
      process.stdout.write(JSON.stringify(uris));
    });
  ")

# Check if already registered
if echo "$CURRENT" | grep -q "$CALLBACK_URL"; then
  echo "→ Callback URI already registered, skipping."
  exit 0
fi

# Append and update
UPDATED=$(node -e "
  const uris = $CURRENT;
  uris.push('$CALLBACK_URL');
  process.stdout.write(JSON.stringify(uris));
")

curl -sf -X PUT \
  "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/access/apps/${SAAS_APP_ID}" \
  -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"type\":\"saas\",\"name\":\"MCP OAuth Provider\",\"saas_app\":{\"auth_type\":\"oidc\",\"redirect_uris\":${UPDATED},\"grant_types\":[\"authorization_code\",\"refresh_tokens\"],\"scopes\":[\"openid\",\"email\",\"profile\",\"groups\"],\"refresh_token_options\":{\"lifetime\":\"90d\"},\"access_token_lifetime\":\"1h\"}}" \
  | node -e "let d=''; process.stdin.on('data',c=>d+=c).on('end',()=>{ const r=JSON.parse(d); console.log(r.success ? '→ Callback URI registered.' : '✗ Failed: '+JSON.stringify(r.errors)); })"
