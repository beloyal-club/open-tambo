# Fly.io Deployment Guide for Tambo Cloud

Complete step-by-step guide for deploying the Tambo Cloud platform (NestJS API + Next.js web) to Fly.io with Fly Postgres and Tigris object storage.

## Architecture Overview

```
Internet
   │
   ├── tambo-web.fly.dev  (Next.js, public)
   │        │ internal DNS
   │        ▼
   ├── tambo-api.internal:3000  (NestJS, private)
   │        │
   │        ├── tambo-db.internal:5432  (Fly Postgres, private)
   │        └── Tigris S3 bucket  (managed object storage)
```

All services communicate over Fly.io's WireGuard-based private network (6PN). Only `tambo-web` is exposed to the public internet. The API runs on the private network, accessible from web and from your machine via `flyctl proxy`.

**Fly apps to create:**
| App name | Source image | Public? | CPU/Memory |
|---|---|---|---|
| `tambo-db` | Fly Postgres | No | shared-cpu-1x / 256 MB (starter) |
| `tambo-api` | `ghcr.io/tambo-ai/tambo-api-server:latest` | No | shared-cpu-1x / 512 MB |
| `tambo-web` | `ghcr.io/tambo-ai/tambo-web-server:latest` | Yes | shared-cpu-1x / 512 MB |

---

## Prerequisites

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Authenticate
fly auth login

# Verify org/account
fly auth whoami
```

Set a shell variable for your org (replace with your actual org slug):
```bash
export FLY_ORG=personal  # or your org name
export FLY_REGION=iad    # choose closest: iad (US East), lax, ord, fra, sin, syd
```

---

## Step 1: Create the Fly Apps (without deploying)

Create placeholder apps first so Fly allocates internal DNS names and shared secrets can be wired up before the first deploy.

```bash
# Create API app
fly apps create tambo-api --org $FLY_ORG

# Create web app
fly apps create tambo-web --org $FLY_ORG
```

---

## Step 2: Provision Fly Postgres

```bash
fly postgres create \
  --name tambo-db \
  --org $FLY_ORG \
  --region $FLY_REGION \
  --vm-size shared-cpu-1x \
  --volume-size 10 \
  --initial-cluster-size 1

# Save the output! It contains:
#   Hostname: tambo-db.internal
#   Flycast: fdaa:...:3
#   Username: postgres
#   Password: <generated>
#   Database: tambo_db (note: Fly names it differently from POSTGRES_DB)
#   Connection string: postgres://postgres:<pass>@tambo-db.internal:5432
```

> **Important:** Fly Postgres creates a database named `<app-name>` (i.e., `tambo_db`). You can create the `tambo` database after attaching:

```bash
# Attach to API app — this automatically creates DATABASE_URL secret on tambo-api
fly postgres attach tambo-db --app tambo-api

# Create the correct database name
fly postgres connect -a tambo-db
# Inside psql:
CREATE DATABASE tambo;
\q

# Update the DATABASE_URL secret to point at 'tambo' db (see Step 4)
```

---

## Step 3: Provision Tigris Object Storage (replaces MinIO)

Tigris is Fly.io's globally-distributed S3-compatible object storage. It's the right replacement for MinIO in production.

```bash
# Create a Tigris bucket attached to the API app
fly storage create \
  --name tambo-user-files \
  --app tambo-api \
  --org $FLY_ORG

# This automatically sets these secrets on tambo-api:
#   AWS_ACCESS_KEY_ID
#   AWS_SECRET_ACCESS_KEY
#   AWS_ENDPOINT_URL_S3
#   AWS_REGION
#   BUCKET_NAME
```

Map these to the env vars the API expects by setting secrets (Step 4).

---

## Step 4: Set Secrets and Environment Variables

### Generate required secrets

```bash
# Generate 32-character secrets (run these locally)
API_KEY_SECRET=$(openssl rand -hex 16)       # 32 hex chars
PROVIDER_KEY_SECRET=$(openssl rand -hex 16)  # 32 hex chars
NEXTAUTH_SECRET=$(openssl rand -base64 32)
echo "API_KEY_SECRET=$API_KEY_SECRET"
echo "PROVIDER_KEY_SECRET=$PROVIDER_KEY_SECRET"
echo "NEXTAUTH_SECRET=$NEXTAUTH_SECRET"
```

### API secrets (`tambo-api`)

```bash
fly secrets set \
  --app tambo-api \
  NODE_ENV=production \
  DATABASE_URL="postgres://postgres:<PASSWORD>@tambo-db.internal:5432/tambo" \
  API_KEY_SECRET="<generated-above>" \
  PROVIDER_KEY_SECRET="<generated-above>" \
  OPENAI_API_KEY="sk-..." \
  EXTRACTION_OPENAI_API_KEY="sk-..." \
  FALLBACK_OPENAI_API_KEY="sk-..." \
  S3_ENDPOINT="<AWS_ENDPOINT_URL_S3 from Tigris>" \
  S3_REGION="auto" \
  S3_ACCESS_KEY_ID="<AWS_ACCESS_KEY_ID from Tigris>" \
  S3_SECRET_ACCESS_KEY="<AWS_SECRET_ACCESS_KEY from Tigris>" \
  S3_BUCKET="tambo-user-files" \
  RESEND_API_KEY="re_..." \
  RESEND_AUDIENCE_ID="..." \
  EMAIL_FROM_DEFAULT="noreply@yourdomain.com" \
  EMAIL_FROM_PERSONAL="hello@yourdomain.com" \
  EMAIL_REPLY_TO_PERSONAL="hello@yourdomain.com" \
  EMAIL_REPLY_TO_SUPPORT="support@yourdomain.com" \
  SENTRY_DSN="https://...@sentry.io/..." \
  POSTHOG_API_KEY="phc_..." \
  POSTHOG_HOST="https://app.posthog.com" \
  LANGFUSE_PUBLIC_KEY="pk-lf-..." \
  LANGFUSE_SECRET_KEY="sk-lf-..." \
  LANGFUSE_HOST="https://cloud.langfuse.com" \
  SLACK_OAUTH_TOKEN="xoxb-..." \
  SLACK_TEAM_ID="T..." \
  INTERNAL_SLACK_USER_ID="U..." \
  DISALLOWED_EMAIL_DOMAINS="" \
  ALLOW_LOCAL_MCP_SERVERS="false" \
  DEPLOY_ENV="production" \
  ENABLE_HSTS="true"
```

### Web secrets (`tambo-web`)

The web app needs DATABASE_URL (for NextAuth session storage) and must know the API's internal URL.

```bash
fly secrets set \
  --app tambo-web \
  NODE_ENV=production \
  DATABASE_URL="postgres://postgres:<PASSWORD>@tambo-db.internal:5432/tambo" \
  API_KEY_SECRET="<same-as-api>" \
  PROVIDER_KEY_SECRET="<same-as-api>" \
  NEXTAUTH_SECRET="<generated-above>" \
  NEXTAUTH_URL="https://tambo-web.fly.dev" \
  GOOGLE_CLIENT_ID="<your-google-client-id>.apps.googleusercontent.com" \
  GOOGLE_CLIENT_SECRET="GOCSPX-..." \
  GITHUB_CLIENT_ID="Iv1..." \
  GITHUB_CLIENT_SECRET="..." \
  RESEND_API_KEY="re_..." \
  RESEND_AUDIENCE_ID="..." \
  EMAIL_FROM_DEFAULT="noreply@yourdomain.com" \
  EMAIL_FROM_PERSONAL="hello@yourdomain.com" \
  EMAIL_REPLY_TO_PERSONAL="hello@yourdomain.com" \
  EMAIL_REPLY_TO_SUPPORT="support@yourdomain.com" \
  NEXT_PUBLIC_SENTRY_DSN="https://...@sentry.io/..." \
  NEXT_PUBLIC_SENTRY_ORG="your-sentry-org" \
  NEXT_PUBLIC_SENTRY_PROJECT="tambo-web" \
  WEATHER_API_KEY="..." \
  ALLOW_LOCAL_MCP_SERVERS="false" \
  GITHUB_TOKEN="ghp_..." \
  ALLOWED_LOGIN_DOMAIN=""
```

> **Note on `NEXT_PUBLIC_*` vars:** Next.js bakes `NEXT_PUBLIC_*` values at **build time**, not runtime. Since you're using pre-built Docker images from GHCR, these values were embedded during the GitHub Actions build. For `NEXT_PUBLIC_TAMBO_API_URL` in particular — if the image was built with `http://localhost:8261`, you need to rebuild the web image with the correct Fly URL before deploying. See the [Rebuilding Images](#rebuilding-images-for-next_public_-vars) section below.

### Setting runtime-safe NEXT_PUBLIC vars via fly.toml env

As a workaround for vars that can be overridden at the Next.js server layer (not truly public client vars), set them in `fly.toml` under `[env]`. For actual browser-side vars embedded at build time, you must rebuild.

---

## Step 5: Create fly.toml Files

### `apps/api/fly.toml`

```toml
app = 'tambo-api'
primary_region = 'iad'

[build]
  image = 'ghcr.io/tambo-ai/tambo-api-server:latest'

[env]
  PORT = '3000'
  NODE_ENV = 'production'
  DEPLOY_ENV = 'production'

[http_service]
  # API is NOT publicly exposed — internal only via private networking
  # Use fly proxy or expose via web app
  internal_port = 3000
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 1

  [[http_service.checks]]
    grace_period = '30s'
    interval = '15s'
    method = 'GET'
    path = '/health'
    timeout = '10s'

[[vm]]
  memory = '512mb'
  cpu_kind = 'shared'
  cpus = 1
```

> **Warning:** The `[http_service]` block makes the app publicly reachable. To make the API truly private (internal only), **remove the `[http_service]` block entirely** and add a `[[services]]` block with `internal_port` only. However, Fly health checks require HTTP. A pragmatic approach: keep `[http_service]` but add IP restriction at the app level, or use Fly's `flycast` feature for private load balancing.

#### Making the API private with Flycast

Flycast gives the app a private IPv6 address accessible only within the org's 6PN:

```bash
# Allocate a private Flycast address for the API
fly ips allocate-v6 --private --app tambo-api
# Returns something like: fdaa:0:1234::3

# The web app then reaches the API via:
# http://tambo-api.flycast:3000
# or via internal DNS: http://tambo-api.internal:3000
```

If using Flycast, update `NEXT_PUBLIC_TAMBO_API_URL` to the flycast address for server-side calls, and expose a separate public endpoint for client-side calls (or proxy through the web app's API routes).

### `apps/web/fly.toml`

```toml
app = 'tambo-web'
primary_region = 'iad'

[build]
  image = 'ghcr.io/tambo-ai/tambo-web-server:latest'

[env]
  PORT = '3000'
  NODE_ENV = 'production'
  # Server-side API URL (internal network — no internet roundtrip)
  NEXT_PUBLIC_TAMBO_API_URL = 'http://tambo-api.internal:3000'

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = 'stop'
  auto_start_machines = true
  min_machines_running = 1

  [[http_service.checks]]
    grace_period = '30s'
    interval = '15s'
    method = 'GET'
    path = '/'
    timeout = '10s'

[[vm]]
  memory = '512mb'
  cpu_kind = 'shared'
  cpus = 1
```

---

## Step 6: Run Database Migrations

Before the first deploy, you need to run Drizzle migrations against the Fly Postgres instance.

### Option A: Via flyctl proxy + local migration (recommended for first run)

```bash
# Open a WireGuard tunnel to Fly Postgres on local port 15432
fly proxy 15432:5432 -a tambo-db &

# Set local DATABASE_URL pointing through the proxy
export DATABASE_URL="postgres://postgres:<PASSWORD>@localhost:15432/tambo"

# Run migrations from repo root
npm run db:migrate -w packages/db

# Kill the proxy
kill %1
```

### Option B: Via a one-off Fly Machine (release_command)

Add a `release_command` to `apps/api/fly.toml` so migrations run automatically before each deploy:

```toml
[deploy]
  release_command = 'node -e "require(\"./scripts/cloud/run-migrations.js\")"'
```

However, the existing `init-database.sh` script runs inside Docker Compose. For Fly, the cleanest approach is to run migrations as part of the API startup. Alternatively, add a dedicated `migrate` script to `apps/api/package.json` that Fly can invoke:

```toml
[deploy]
  release_command = 'sh -c "cd /app && DATABASE_URL=$DATABASE_URL npx drizzle-kit migrate --config packages/db/drizzle.config.ts"'
```

Check `packages/db/package.json` for the exact migrate command and adapt accordingly.

---

## Step 7: First Deployment

### Deploy API

```bash
cd tambo  # repo root

# Deploy using the fly.toml in apps/api
fly deploy --app tambo-api \
  --config apps/api/fly.toml \
  --image ghcr.io/tambo-ai/tambo-api-server:latest

# Monitor deployment
fly status --app tambo-api
fly logs --app tambo-api
```

### Deploy Web

```bash
fly deploy --app tambo-web \
  --config apps/web/fly.toml \
  --image ghcr.io/tambo-ai/tambo-web-server:latest

# Monitor deployment
fly status --app tambo-web
fly logs --app tambo-web
```

### Verify health

```bash
# Check API health (via proxy since it's internal)
fly proxy 8261:3000 -a tambo-api &
curl http://localhost:8261/health
kill %1

# Check web (public)
curl https://tambo-web.fly.dev/
```

---

## Step 8: Custom Domains

```bash
# Add custom domain to web app
fly certs add yourdomain.com --app tambo-web
fly certs add www.yourdomain.com --app tambo-web

# Get the DNS records to configure at your registrar
fly certs show yourdomain.com --app tambo-web
# Output shows CNAME/A/AAAA records to add

# If you want a custom domain for the API (only needed if exposing it publicly)
fly certs add api.yourdomain.com --app tambo-api
```

After adding the cert:
1. Add the DNS records at your domain registrar (CNAME pointing to `tambo-web.fly.dev`)
2. Update `NEXTAUTH_URL` secret: `fly secrets set NEXTAUTH_URL="https://yourdomain.com" --app tambo-web`
3. Update Google OAuth authorized redirect URIs to include `https://yourdomain.com/api/auth/callback/google`
4. Redeploy: `fly deploy --app tambo-web --config apps/web/fly.toml --image ghcr.io/tambo-ai/tambo-web-server:latest`

---

## Step 9: Networking Details

### How web reaches API

The Next.js app calls the API in two contexts:

1. **Server-side (SSR/API routes):** Uses `NEXT_PUBLIC_TAMBO_API_URL=http://tambo-api.internal:3000` — routes through Fly's 6PN, zero latency, no internet exposure.

2. **Client-side (browser):** The browser cannot reach `tambo-api.internal`. Options:
   - **Proxy through web app:** Add Next.js rewrites so `/api/tambo/*` proxies to the internal API. This keeps the API private.
   - **Expose API publicly:** Give `tambo-api` a public IP and set `NEXT_PUBLIC_TAMBO_API_URL` to `https://api.yourdomain.com` at build time.

#### Recommended: Next.js rewrite proxy

Add to `apps/web/next.config.mjs`:

```js
async rewrites() {
  return [
    {
      source: '/api/tambo/:path*',
      destination: `${process.env.TAMBO_API_INTERNAL_URL}/:path*`,
    },
  ]
}
```

Then set `NEXT_PUBLIC_TAMBO_API_URL=/api/tambo` (browser-relative) and `TAMBO_API_INTERNAL_URL=http://tambo-api.internal:3000` (server-only).

### Internal DNS names

Fly.io automatically provides these internal hostnames within the org's 6PN:

| Service | Internal hostname | Port |
|---|---|---|
| API | `tambo-api.internal` | 3000 |
| Postgres | `tambo-db.internal` | 5432 |
| Web | `tambo-web.internal` | 3000 |

Multiple machines of the same app are accessible via `<app>.internal` (Fly load-balances) or by individual machine ID.

---

## Step 10: Storage (Tigris CORS Configuration)

Since the API uses presigned URLs for direct browser uploads (see `devdocs/STORAGE_SETUP.md`), configure CORS on the Tigris bucket to allow PUT from your web domain:

```bash
# Install AWS CLI if not present
# Configure with Tigris credentials
aws configure set aws_access_key_id <TIGRIS_ACCESS_KEY>
aws configure set aws_secret_access_key <TIGRIS_SECRET_KEY>
aws configure set default.region auto

# Apply CORS policy
aws s3api put-bucket-cors \
  --endpoint-url <TIGRIS_ENDPOINT> \
  --bucket tambo-user-files \
  --cors-configuration '{
    "CORSRules": [
      {
        "AllowedOrigins": ["https://tambo-web.fly.dev", "https://yourdomain.com"],
        "AllowedMethods": ["PUT", "GET"],
        "AllowedHeaders": ["Content-Type", "Content-Length"],
        "MaxAgeSeconds": 3600
      }
    ]
  }'
```

---

## CI/CD Integration

### Extend `.github/workflows/docker.yml`

Add a `deploy` job that runs after the existing `test` job on pushes to `main`, or after a release `push` job:

```yaml
# Add to .github/workflows/docker.yml, after the existing 'push' job

  deploy:
    name: Deploy to Fly.io
    needs: [meta, build, test, push]
    # Deploy on push to main OR when a release is published
    if: |
      always() &&
      needs.test.result == 'success' &&
      (github.event_name == 'push' && github.ref == 'refs/heads/main' ||
       github.event_name == 'release')
    runs-on: ubuntu-latest
    environment: production   # uses GitHub Environment for approval gates
    permissions:
      contents: read
      packages: read
    env:
      FLY_API_TOKEN: ${{ secrets.FLY_API_TOKEN }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v6

      - name: Set up flyctl
        uses: superfly/flyctl-actions/setup-flyctl@master

      - name: Determine image tag
        id: image-tag
        run: |
          if [[ "${{ github.event_name }}" == "release" ]]; then
            # Use the version tag from the release (e.g., "0.144.5")
            TAG="${{ github.event.release.tag_name }}"
            # Strip service prefix: "api-v0.144.5" -> "0.144.5"
            VERSION="${TAG#*-v}"
            echo "tag=$VERSION" >> $GITHUB_OUTPUT
          else
            # Use short SHA for branch deploys
            echo "tag=sha-$(echo ${{ github.sha }} | head -c7)" >> $GITHUB_OUTPUT
          fi

      - name: Deploy API to Fly.io
        if: |
          needs.meta.outputs.release-service == 'all' ||
          needs.meta.outputs.release-service == 'api' ||
          github.event_name == 'push'
        run: |
          fly deploy \
            --app tambo-api \
            --config apps/api/fly.toml \
            --image ghcr.io/tambo-ai/tambo-api-server:${{ steps.image-tag.outputs.tag }} \
            --strategy rolling \
            --wait-timeout 300

      - name: Deploy Web to Fly.io
        if: |
          needs.meta.outputs.release-service == 'all' ||
          needs.meta.outputs.release-service == 'web' ||
          github.event_name == 'push'
        run: |
          fly deploy \
            --app tambo-web \
            --config apps/web/fly.toml \
            --image ghcr.io/tambo-ai/tambo-web-server:${{ steps.image-tag.outputs.tag }} \
            --strategy rolling \
            --wait-timeout 300

      - name: Verify deployment health
        run: |
          # Check API via proxy
          fly proxy 8261:3000 -a tambo-api -- &
          PROXY_PID=$!
          sleep 5
          curl -fso /dev/null http://localhost:8261/health || \
            (echo "API health check failed" && kill $PROXY_PID && exit 1)
          kill $PROXY_PID

          # Check web
          curl -fso /dev/null https://tambo-web.fly.dev/ || \
            (echo "Web health check failed" && exit 1)

          echo "Deployment verified successfully"
```

### Required GitHub Secrets

Add these in your GitHub repo → Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `FLY_API_TOKEN` | From `fly tokens create deploy -x 999999h` |
| `RELEASE_PACKAGES` | Already exists (for GHCR push) |
| `TURBO_TOKEN` | Already exists |

```bash
# Generate a long-lived deploy token
fly tokens create deploy -x 999999h --name "github-actions"
# Copy the output to GitHub secret FLY_API_TOKEN
```

### Deployment strategy

The `--strategy rolling` flag (default) replaces machines one at a time, maintaining uptime. For zero-downtime deploys with database migrations, ensure the API is backward-compatible with both old and new schema during the rollover window.

---

## Scaling Considerations

### Vertical scaling (VM size)

```bash
# Scale API to more memory for LLM workloads
fly scale memory 1024 --app tambo-api

# Scale to dedicated CPU for consistent performance
fly scale vm performance-1x --app tambo-api
```

### Horizontal scaling (multiple machines)

```bash
# Run 2 API machines for redundancy
fly scale count 2 --app tambo-api --region iad

# Run 2 web machines
fly scale count 2 --app tambo-web --region iad
```

### Auto-scaling

The `auto_stop_machines = 'stop'` and `auto_start_machines = true` settings in `fly.toml` enable Fly's autoscaler — machines stop when idle and start on new requests. For production with consistent traffic, set `min_machines_running = 1` (already in the config above) to avoid cold starts.

### Postgres scaling

```bash
# Upgrade Postgres volume size
fly volumes extend <volume-id> --size 20 --app tambo-db

# Add a read replica (for read-heavy workloads)
fly postgres create --name tambo-db-replica --fork-from tambo-db --region fra
```

### Multi-region

For global users, deploy to multiple regions:

```bash
# Add a secondary region for web
fly regions add fra --app tambo-web
fly scale count 3 --app tambo-web  # 3 machines spread across regions

# For the API, add machines in the same regions as web
fly regions add fra --app tambo-api
fly scale count 3 --app tambo-api
```

---

## Rebuilding Images for `NEXT_PUBLIC_*` Vars

`NEXT_PUBLIC_*` env vars are inlined at Next.js **build time**. The pre-built GHCR images were built with `http://localhost:8261` as `NEXT_PUBLIC_TAMBO_API_URL`, which won't work in production.

### Fix: Use Next.js rewrites (no rebuild needed)

This is the cleanest approach — keep `NEXT_PUBLIC_TAMBO_API_URL` as a relative path and proxy to the internal API:

In `apps/web/next.config.mjs`, add rewrites pointing to `process.env.TAMBO_API_INTERNAL_URL` (a server-only env var, not `NEXT_PUBLIC_*`). Set `TAMBO_API_INTERNAL_URL=http://tambo-api.internal:3000` as a Fly secret.

### Fix: Rebuild the web image with correct env vars

If you need the URL embedded at build time (e.g., for SDK calls that happen purely in the browser with no proxy):

```bash
# Build locally with production values
docker build \
  --build-arg NODE_ENV=production \
  --build-arg NEXT_PUBLIC_TAMBO_API_URL=https://api.yourdomain.com \
  -t ghcr.io/tambo-ai/tambo-web-server:custom \
  -f apps/web/Dockerfile \
  .

# Push to GHCR
docker push ghcr.io/tambo-ai/tambo-web-server:custom

# Deploy with this tag
fly deploy --app tambo-web \
  --config apps/web/fly.toml \
  --image ghcr.io/tambo-ai/tambo-web-server:custom
```

In GitHub Actions, pass `NEXT_PUBLIC_TAMBO_API_URL` as a build arg:

```yaml
build-args: |
  NODE_ENV=production
  TURBO_TEAM=${{ vars.TURBO_TEAM }}
  NEXT_PUBLIC_TAMBO_API_URL=${{ vars.NEXT_PUBLIC_TAMBO_API_URL }}
```

And add `NEXT_PUBLIC_TAMBO_API_URL` as a GitHub Actions variable (not secret, it's public).

---

## Operational Runbook

### View logs

```bash
fly logs --app tambo-api
fly logs --app tambo-web
fly logs --app tambo-db
```

### Open a psql shell to Postgres

```bash
fly postgres connect -a tambo-db -d tambo
```

### Run a one-off migration

```bash
fly proxy 15432:5432 -a tambo-db &
DATABASE_URL="postgres://postgres:<pass>@localhost:15432/tambo" \
  npm run db:migrate -w packages/db
kill %1
```

### SSH into a running machine

```bash
fly ssh console --app tambo-api
fly ssh console --app tambo-web
```

### Restart an app

```bash
fly apps restart tambo-api
fly apps restart tambo-web
```

### Check machine status

```bash
fly status --app tambo-api
fly status --app tambo-web
fly machines list --app tambo-api
```

### Scale down to zero (save cost when idle)

```bash
fly scale count 0 --app tambo-api
fly scale count 0 --app tambo-web
```

### Rollback to a previous image

```bash
# List recent releases
fly releases --app tambo-api

# Rollback to a specific version
fly deploy \
  --app tambo-api \
  --config apps/api/fly.toml \
  --image ghcr.io/tambo-ai/tambo-api-server:0.143.0
```

---

## Complete First-Deploy Checklist

```
[ ] fly auth login
[ ] fly apps create tambo-api
[ ] fly apps create tambo-web
[ ] fly postgres create --name tambo-db (save credentials)
[ ] fly postgres attach tambo-db --app tambo-api
[ ] Create 'tambo' database in psql
[ ] fly storage create --name tambo-user-files --app tambo-api
[ ] fly secrets set (all API secrets)
[ ] fly secrets set (all web secrets)
[ ] Create apps/api/fly.toml
[ ] Create apps/web/fly.toml
[ ] Run database migrations via proxy
[ ] fly deploy tambo-api
[ ] fly deploy tambo-web
[ ] Verify /health and / endpoints
[ ] Configure Tigris CORS
[ ] fly certs add (custom domain)
[ ] Update NEXTAUTH_URL secret with custom domain
[ ] Update Google/GitHub OAuth redirect URIs
[ ] Add FLY_API_TOKEN to GitHub secrets
[ ] Add deploy job to .github/workflows/docker.yml
[ ] Test end-to-end: sign in, create project, use API
```

---

## Cost Estimate (Fly.io shared-cpu tier)

| Resource | Config | Monthly cost |
|---|---|---|
| tambo-api | shared-cpu-1x, 512MB, 1 machine | ~$3-5 |
| tambo-web | shared-cpu-1x, 512MB, 1 machine | ~$3-5 |
| tambo-db | shared-cpu-1x, 256MB, 10GB volume | ~$5-10 |
| Tigris storage | First 5GB free | $0-2 |
| **Total** | | **~$11-22/month** |

With `auto_stop_machines = 'stop'` and low traffic, costs can be near zero — machines only run when handling requests.

Scale to 2 machines each + dedicated CPU + 20GB Postgres volume for a production-grade setup: ~$50-80/month.
