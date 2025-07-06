#!/bin/bash

# Stop all Chat E2EE services

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Stopping Chat E2EE services...${NC}"

cd "$(dirname "$0")/../docker"
docker-compose down

echo -e "${GREEN}Services stopped!${NC}"
