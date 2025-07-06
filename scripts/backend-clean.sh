#!/bin/bash

# Clean and rebuild backend for Chat E2EE

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Cleaning and Rebuilding Backend ===${NC}\n"

# Navigate to src directory
cd "$(dirname "$0")/../src"

# Clean Go cache
echo -e "${YELLOW}Cleaning Go cache...${NC}"
go clean -cache
go clean -modcache

# Remove old files
echo -e "${YELLOW}Removing old files...${NC}"
rm -f go.sum
rm -rf vendor/
rm -rf tmp/

# Re-initialize
echo -e "${YELLOW}Re-initializing Go module...${NC}"
go mod download
go mod tidy

# Navigate to docker directory
cd ../docker

# Stop and remove old backend container
echo -e "\n${YELLOW}Removing old backend container...${NC}"
docker-compose stop backend
docker-compose rm -f backend

# Remove old image
echo -e "${YELLOW}Removing old backend image...${NC}"
docker rmi docker_backend 2>/dev/null || true

# Build fresh
echo -e "\n${YELLOW}Building fresh backend image...${NC}"
docker-compose build --no-cache backend

echo -e "\n${GREEN}Clean rebuild complete!${NC}"
echo -e "${YELLOW}Now run:${NC} ./scripts/backend-start.sh"