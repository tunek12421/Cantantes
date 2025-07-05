#!/bin/bash

# Quick PostgreSQL access for Chat E2EE

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

# If argument provided, execute it as SQL
if [ -n "$1" ]; then
    docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "$1"
else
    # Interactive psql session
    docker-compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"
fi