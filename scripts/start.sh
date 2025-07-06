#!/bin/bash

# Start all Chat E2EE services

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Starting Chat E2EE services...${NC}"

cd "$(dirname "$0")/../docker"

# Check .env
if [ ! -f ".env" ]; then
    echo -e "${RED}Error: .env not found! Run ./scripts/init.sh first${NC}"
    exit 1
fi

# Start services
docker-compose up -d

# Wait for services
echo -e "\n${YELLOW}Waiting for services...${NC}"
sleep 5

# Quick status check
echo -e "\n${GREEN}Services started!${NC}"
docker-compose ps

echo -e "\nRun ./scripts/status.sh for detailed status"
