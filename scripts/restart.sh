#!/bin/bash

# Quick restart script for Chat E2EE services

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Check if .env exists
if [ ! -f ".env" ]; then
    log_error ".env file not found!"
    exit 1
fi

# Stop all services
log_info "Stopping all services..."
docker-compose down

# Remove any problematic volumes if specified
if [ "$1" == "--clean" ]; then
    log_info "Cleaning data volumes..."
    read -p "Are you sure you want to delete all data? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker volume rm docker_postgres_data docker_redis_data docker_minio_data 2>/dev/null || true
        log_info "Volumes cleaned"
    fi
fi

# Start services again
log_info "Starting services..."
docker-compose up -d

# Load environment
set -a
source .env
set +a

# Wait for services
log_info "Waiting for services to be ready..."
echo -n "Waiting for PostgreSQL: "
for i in {1..30}; do
    if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &> /dev/null; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

if [ $i -eq 30 ]; then
    echo -e " ${RED}✗${NC}"
    log_error "PostgreSQL did not start properly"
fi

sleep 2

# Check health
../scripts/health-check.sh

log_info "Restart complete!"