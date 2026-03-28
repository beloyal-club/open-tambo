#!/bin/bash

# Build Tambo Docker Containers
# This script builds all containers for the Tambo application

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_cloud-helpers.sh"

REPO_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT_DIR"

info "🔨 Building Tambo Docker Containers..."
info "📁 Working directory: $(pwd)"

# Check if docker.env exists
if [ ! -f "docker.env" ]; then
    fail \
      "❌ docker.env file not found!" \
      "📝 Please copy docker.env.example to docker.env and update with your values"
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    fail "❌ Docker is not running. Please start Docker first."
fi

# Build all containers with BuildKit
info "🚀 Building containers with BuildKit..."

# Check if running in GitHub Actions
if [ -n "$GITHUB_ACTIONS" ]; then
    info "📦 Using GitHub Actions environment with caching..."
    # The docker-compose.yml now includes proper caching configuration
    DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 docker compose --env-file docker.env build
else
    info "📦 Using default Docker caching..."
    DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 docker compose --env-file docker.env build
fi

success \
  "✅ Build completed!" \
  "💡 To start the containers: ./scripts/cloud/tambo-start.sh" 
