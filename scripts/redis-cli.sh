#!/bin/bash

# Quick Redis/KeyDB access for Chat E2EE

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Load environment
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
else
    echo "Error: .env file not found"
    exit 1
fi

# Connect to Redis with authentication
if [ -n "$REDIS_PASSWORD" ]; then
    docker-compose exec redis keydb-cli -a "$REDIS_PASSWORD" "$@"
else
    docker-compose exec redis keydb-cli "$@"
fi