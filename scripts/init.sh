#!/bin/bash

# Initialize Chat E2EE project

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Chat E2EE Initialization ===${NC}\n"

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed!${NC}"
    echo "Install from: https://docs.docker.com/engine/install/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Docker Compose is not installed!${NC}"
    exit 1
fi

# Create directories
echo -e "${YELLOW}Creating directories...${NC}"
mkdir -p data/{postgres,redis,minio,pgadmin} logs/{postgres,redis,minio,backend}

# Create .env if doesn't exist
if [ ! -f "docker/.env" ]; then
    echo -e "${YELLOW}Creating .env file...${NC}"
    cp docker/.env.example docker/.env
    
    # Generate passwords
    generate_password() {
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
    }
    
    # Replace passwords
    sed -i "s/change_this_strong_password_123!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_redis_password_456!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_minio_password_789!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_pgadmin_password!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_jwt_secret_key_very_long_and_random!/$(generate_password)$(generate_password)/g" docker/.env
    sed -i "s/change_this_server_encryption_key!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_backup_encryption_key!/$(generate_password)/g" docker/.env
    
    echo -e "${GREEN}✓ .env created with secure passwords${NC}"
    echo -e "${YELLOW}⚠ Remember to add your SMS credentials!${NC}"
fi

# Set permissions
chmod 600 docker/.env
sudo chown -R 999:999 data/postgres 2>/dev/null || true
sudo chown -R 999:999 data/redis 2>/dev/null || true
sudo chown -R 1000:1000 data/minio 2>/dev/null || true

echo -e "\n${GREEN}Initialization complete!${NC}"
echo "Run: ./scripts/start.sh"
