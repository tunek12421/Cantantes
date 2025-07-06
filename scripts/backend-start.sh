#!/bin/bash

# Start backend service for Chat E2EE

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Starting Chat E2EE Backend ===${NC}\n"

# Check if go.sum exists
if [ ! -f "$(dirname "$0")/../src/go.sum" ]; then
    echo -e "${YELLOW}go.sum not found. Initializing backend...${NC}"
    "$(dirname "$0")/backend-init.sh"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to initialize backend${NC}"
        exit 1
    fi
fi

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Check if services are running
echo -e "${YELLOW}Checking required services...${NC}"

# Check PostgreSQL
if docker-compose ps postgres | grep -q "Up"; then
    echo -e "${GREEN}✓ PostgreSQL is running${NC}"
else
    echo -e "${RED}✗ PostgreSQL is not running${NC}"
    echo "Starting PostgreSQL..."
    docker-compose up -d postgres
    sleep 5
fi

# Check Redis
if docker-compose ps redis | grep -q "Up"; then
    echo -e "${GREEN}✓ Redis is running${NC}"
else
    echo -e "${RED}✗ Redis is not running${NC}"
    echo "Starting Redis..."
    docker-compose up -d redis
fi

# Check MinIO
if docker-compose ps minio | grep -q "Up"; then
    echo -e "${GREEN}✓ MinIO is running${NC}"
else
    echo -e "${RED}✗ MinIO is not running${NC}"
    echo "Starting MinIO..."
    docker-compose up -d minio
fi

# Build and start backend
echo -e "\n${YELLOW}Building backend...${NC}"
docker-compose build backend

echo -e "\n${YELLOW}Starting backend...${NC}"
docker-compose up -d backend

# Wait for backend to be ready
echo -e "\n${YELLOW}Waiting for backend to be ready...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "\n${GREEN}✓ Backend is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

if [ $i -eq 30 ]; then
    echo -e "\n${RED}✗ Backend did not start properly${NC}"
    echo "Checking logs..."
    docker-compose logs --tail=20 backend
    exit 1
fi

# Show status
echo -e "\n${GREEN}=== Backend Status ===${NC}"
docker-compose ps backend

echo -e "\n${GREEN}API Endpoints:${NC}"
echo "- Health: http://localhost:8080/health"
echo "- API: http://localhost:8080/api/v1"

echo -e "\n${YELLOW}View logs:${NC} docker-compose logs -f backend"
echo -e "${YELLOW}Stop backend:${NC} docker-compose stop backend"