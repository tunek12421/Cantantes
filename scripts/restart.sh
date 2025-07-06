#!/bin/bash

# Restart Chat E2EE services

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Restarting services...${NC}"

cd "$(dirname "$0")/../docker"
docker-compose restart

echo -e "${GREEN}Services restarted!${NC}"
