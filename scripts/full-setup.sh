#!/bin/bash

# Full setup script for Chat E2EE
# This script handles the complete installation from scratch

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Chat E2EE Full Setup ===${NC}\n"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Function to print steps
step() {
    echo -e "\n${YELLOW}Step $1: $2${NC}"
}

# Check prerequisites
step "1" "Checking prerequisites"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed!${NC}"
    echo "Please install Docker first: https://docs.docker.com/engine/install/ubuntu/"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Docker Compose is not installed!${NC}"
    echo "Please install Docker Compose first"
    exit 1
fi

# Check if Docker daemon is running
if ! docker info &> /dev/null; then
    echo -e "${RED}Docker daemon is not running!${NC}"
    echo "Start it with: sudo systemctl start docker"
    exit 1
fi

echo -e "${GREEN}✓ Docker and Docker Compose are installed and running${NC}"

# Create directory structure
step "2" "Creating directory structure"
cd "$PROJECT_DIR"
mkdir -p {docker/{postgres/init,redis,minio},data/{postgres,redis,minio,pgadmin},logs/{postgres,redis,minio},scripts}
echo -e "${GREEN}✓ Directory structure created${NC}"

# Make scripts executable
step "3" "Setting script permissions"
chmod +x scripts/*.sh 2>/dev/null || true
# Verify all scripts are executable
find scripts -name "*.sh" -exec chmod +x {} \;
echo -e "${GREEN}✓ Script permissions set${NC}"

# Stop any existing containers
step "4" "Cleaning up any existing containers"
cd docker
docker-compose down 2>/dev/null || true
cd ..

# Setup environment file
step "5" "Setting up environment configuration"
if [ ! -f "docker/.env" ]; then
    if [ -f "scripts/setup-env.sh" ]; then
        ./scripts/setup-env.sh
    else
        echo -e "${RED}setup-env.sh not found!${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}Environment file already exists${NC}"
fi

# Fix docker-compose.yml if needed
step "6" "Fixing docker-compose.yml"
if grep -q "^version:" docker/docker-compose.yml 2>/dev/null; then
    echo "Removing obsolete version line..."
    sed -i '1d' docker/docker-compose.yml
fi
echo -e "${GREEN}✓ docker-compose.yml is correct${NC}"

# Set proper permissions
step "7" "Setting directory permissions"
sudo chown -R $USER:$USER data/ logs/ 2>/dev/null || true
sudo chown -R 999:999 data/postgres 2>/dev/null || true
sudo chown -R 999:999 data/redis 2>/dev/null || true
sudo chown -R 1000:1000 data/minio 2>/dev/null || true
echo -e "${GREEN}✓ Directory permissions set${NC}"

# Start services
step "8" "Starting Docker services"
cd docker

# Pull images first
echo "Pulling Docker images..."
docker-compose pull

# Start services
echo "Starting containers..."
docker-compose up -d

# Load environment variables
set -a
source .env
set +a

# Wait for PostgreSQL
echo -e "\n${YELLOW}Waiting for PostgreSQL to initialize...${NC}"
echo -n "This may take up to 60 seconds on first run: "
for i in {1..60}; do
    if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &> /dev/null; then
        echo -e "\n${GREEN}✓ PostgreSQL is ready${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

if [ $i -eq 60 ]; then
    echo -e "\n${RED}PostgreSQL did not start in time${NC}"
    echo "Checking logs..."
    docker-compose logs --tail=20 postgres
fi

# Initialize database if needed
if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &> /dev/null; then
    echo "Checking database initialization..."
    if ! docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt" 2>&1 | grep -q "users"; then
        echo "Initializing database schema..."
        docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < ./postgres/init/01-init.sql 2>&1 || true
    fi
fi

cd ..

# Final setup steps
step "9" "Running final initialization"
./scripts/init.sh

# Summary
echo -e "\n${BLUE}=== Setup Complete ===${NC}\n"

# Run health check
./scripts/health-check.sh

echo -e "\n${GREEN}=== Next Steps ===${NC}"
echo "1. Update SMS credentials in docker/.env:"
echo "   nano docker/.env"
echo ""
echo "2. Check service status:"
echo "   ./scripts/health-check.sh"
echo ""
echo "3. View logs:"
echo "   ./scripts/logs.sh [service]"
echo ""
echo "4. Access services:"
echo "   - PostgreSQL: localhost:5432"
echo "   - Redis: localhost:6379"
echo "   - MinIO Console: http://localhost:9001"
echo "   - pgAdmin: http://localhost:5050"
echo ""
echo -e "${GREEN}Happy coding! 🚀${NC}"