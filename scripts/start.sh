#!/bin/bash

# Quick start for Chat E2EE services

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Starting Chat E2EE services...${NC}"

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Run: ./scripts/setup-env.sh first"
    exit 1
fi

# Start all services
docker-compose up -d

# Wait a moment
sleep 5

# Quick health check
echo -e "\n${YELLOW}Quick health check:${NC}"
docker-compose ps

echo -e "\n${GREEN}Services started!${NC}"
echo "Run ./scripts/health-check.sh for detailed status"