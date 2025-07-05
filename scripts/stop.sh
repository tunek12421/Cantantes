#!/bin/bash

# Stop all Chat E2EE services

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Stopping Chat E2EE services...${NC}"

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Stop all services
docker-compose down

echo -e "${GREEN}All services stopped!${NC}"

# Show what's still running (if anything)
if docker ps | grep -q "chat_"; then
    echo -e "\n${YELLOW}Warning: Some containers are still running:${NC}"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep "chat_"
fi

echo -e "\nTo start services again, run: ./scripts/init.sh"