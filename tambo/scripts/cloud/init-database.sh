#!/usr/bin/env sh

# Initialize Tambo Database
# This script initializes the PostgreSQL database with the required schema.
# It can run either on the host (using Docker to connect to Postgres)
# or inside a running Docker container (e.g., the API container).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_cloud-helpers.sh"

REPO_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT_DIR"

info "🗄️  Initializing Tambo Database..."
info "📁 Working directory: $(pwd)"

# Detect if running inside a Docker container
IS_IN_DOCKER=false
if [ -f "/.dockerenv" ] || grep -qa docker /proc/1/cgroup 2>/dev/null; then
  IS_IN_DOCKER=true
fi

# When running on the host, this script will delegate to the api container.
# When running inside a container, it will run the migrations directly.

if [ "$IS_IN_DOCKER" = false ]; then
  # Host mode: delegate to Docker container
  if [ ! -f "docker.env" ]; then
    fail \
      "❌ docker.env file not found!" \
      "📝 Please copy docker.env.example to docker.env and update with your values"
  fi
  if ! command -v docker >/dev/null 2>&1; then
    fail "❌ Docker is not installed. Please install Docker first."
  fi
  if ! docker info >/dev/null 2>&1; then
    fail "❌ Docker is not running. Please start Docker first."
  fi
  if ! command -v docker compose >/dev/null 2>&1; then
    fail "❌ Docker Compose is not available. Please install Docker Compose."
  fi
  if ! docker compose --env-file docker.env ps api | grep -q "Up"; then
    fail \
      "❌ API container is not running. Please start the stack first:" \
      "   ./scripts/cloud/tambo-start.sh"
  fi

  info "📦 Delegating to api container..."
  exec docker compose --env-file docker.env exec -T api sh -lc "./scripts/cloud/init-database.sh"
fi

# From here on, we are inside a container

# Run database migrations
info "🔄 Running database migrations..."

# In-container mode: rely on DATABASE_URL already present in environment
if [ -z "$DATABASE_URL" ]; then
  fail \
    "❌ DATABASE_URL is not set in the container environment." \
    "   Please ensure your service sets DATABASE_URL, or run this script from the host to auto-delegate into the container."
fi
info "📋 Using container DATABASE_URL: $DATABASE_URL"
info "📊 Running database migrations inside container..."
npm -w @tambo-ai-cloud/db run db:migrate

success \
  "✅ Database initialization completed successfully!" \
  "📋 Database is now ready for use."
