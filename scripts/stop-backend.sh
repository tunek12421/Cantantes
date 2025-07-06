#!/bin/bash

# Stop backend service for Chat E2EE

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Stopping Chat E2EE backend...${NC}"

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Stop backend service only
docker-compose stop backend

echo -e "${GREEN}Backend stopped!${NC}"

# Show what's still running
echo -e "\n${YELLOW}Other services still running:${NC}"
docker-compose ps --format "table {{.Service}}\t{{.Status}}" | grep -E "(SERVICE|Up)"