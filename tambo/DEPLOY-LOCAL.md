# Tambo Local Docker Deployment Guide

## What's been done

A `docker.env` file has been created in your tambo repo with auto-generated secure secrets for:

- `POSTGRES_PASSWORD`
- `API_KEY_SECRET` (32-char)
- `PROVIDER_KEY_SECRET` (32-char)
- `NEXTAUTH_SECRET`

## Step 1: Add your API keys

Open `docker.env` in the tambo folder and replace the three placeholder values:

```
OPENAI_API_KEY=YOUR_OPENAI_API_KEY_HERE
EXTRACTION_OPENAI_API_KEY=YOUR_OPENAI_API_KEY_HERE
FALLBACK_OPENAI_API_KEY=YOUR_OPENAI_API_KEY_HERE
```

Replace all three with your actual OpenAI API key (they can all be the same key).

## Step 2: Add your Google OAuth credentials

Still in `docker.env`, replace:

```
GOOGLE_CLIENT_ID=YOUR_GOOGLE_CLIENT_ID_HERE
GOOGLE_CLIENT_SECRET=YOUR_GOOGLE_CLIENT_SECRET_HERE
```

If you haven't created Google OAuth credentials yet:

1. Go to [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials)
2. Create an **OAuth 2.0 Client ID** (Web application type)
3. Add this as an **Authorized redirect URI**: `http://localhost:8260/api/auth/callback/google`
4. Copy the Client ID and Client Secret into `docker.env`

## Step 3: Build the Docker images

Open a terminal, navigate to the tambo folder, and run:

```bash
cd tambo
./scripts/cloud/tambo-build.sh
```

This builds the `tambo-web` and `tambo-api` Docker images. It may take several minutes the first time.

## Step 4: Start the stack

```bash
./scripts/cloud/tambo-start.sh
```

This starts PostgreSQL, MinIO, the API service, and the web dashboard.

## Step 5: Initialize the database

Wait about 30 seconds for all services to become healthy, then:

```bash
./scripts/cloud/init-database.sh
```

## Step 6: Access your instance

- **Web Dashboard**: http://localhost:8260
- **API Endpoint**: http://localhost:8261
- **MinIO Console**: http://localhost:9001 (user: `minioadmin`, pass: `minioadmin`)

Sign in using your Google account.

## Useful commands

| Action | Command |
|---|---|
| View all logs | `./scripts/cloud/tambo-logs.sh` |
| View API logs only | `./scripts/cloud/tambo-logs.sh api` |
| View web logs only | `./scripts/cloud/tambo-logs.sh web` |
| Stop everything | `./scripts/cloud/tambo-stop.sh` |
| Database CLI | `./scripts/cloud/tambo-psql.sh` |
| Check status | `docker compose --env-file docker.env ps` |

## Deploying to Fly.io

All `fly` commands must be run from the `tambo/` directory, since the Dockerfile paths in `fly.toml` are relative.

```bash
cd tambo

# Deploy the API
fly deploy -c fly.toml

# Deploy the web dashboard
fly deploy -c fly.web.toml
```

## Troubleshooting

**Services won't start?**
Run `docker info` to confirm Docker is running, then check logs with `./scripts/cloud/tambo-logs.sh`.

**Database connection issues?**
Check PostgreSQL health: `docker compose --env-file docker.env ps postgres`

**Auth not working?**
Verify that `NEXTAUTH_URL=http://localhost:8260` (no trailing slash) and your Google OAuth redirect URI matches exactly: `http://localhost:8260/api/auth/callback/google`.

**Full reset:**
```bash
docker compose --env-file docker.env down -v
docker volume rm tambo_tambo_postgres_data
./scripts/cloud/tambo-start.sh
./scripts/cloud/init-database.sh
```
