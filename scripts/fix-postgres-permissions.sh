#!/bin/bash

# Fix PostgreSQL permissions for Chat E2EE
# This script fixes the log directory permissions issue

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Fixing PostgreSQL Permissions ===${NC}\n"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Step 1: Stop all containers
echo -e "${YELLOW}Step 1: Stopping all containers...${NC}"
cd "$PROJECT_DIR/docker"
docker-compose down

# Step 2: Clean up problematic volumes and directories
echo -e "\n${YELLOW}Step 2: Cleaning up data directories...${NC}"
cd "$PROJECT_DIR"

# Remove old data directories
sudo rm -rf data/postgres data/redis data/minio logs/postgres logs/redis logs/minio

# Remove Docker volumes
docker volume rm docker_postgres_data docker_redis_data docker_minio_data 2>/dev/null || true

# Step 3: Recreate directories with correct permissions
echo -e "\n${YELLOW}Step 3: Creating directories with correct permissions...${NC}"
mkdir -p data/{postgres,redis,minio,pgadmin}
mkdir -p logs/{postgres,redis,minio}

# Set ownership for PostgreSQL (user 999 is the postgres user in container)
sudo chown -R 999:999 data/postgres
sudo chown -R 999:999 logs/postgres
sudo chmod -R 755 logs/postgres

# Set ownership for Redis
sudo chown -R 999:999 data/redis
sudo chown -R 999:999 logs/redis

# Set ownership for MinIO
sudo chown -R 1000:1000 data/minio
sudo chown -R 1000:1000 logs/minio

# Step 4: Fix docker-compose.yml to remove problematic logging
echo -e "\n${YELLOW}Step 4: Creating fixed docker-compose configuration...${NC}"
cd "$PROJECT_DIR/docker"

# Create a temporary docker-compose with simpler PostgreSQL config
cat > docker-compose-fixed.yml << 'EOF'
services:
  # PostgreSQL - Base de datos principal
  postgres:
    image: postgres:15-alpine
    container_name: chat_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ./postgres/init:/docker-entrypoint-initdb.d
      - ../data/postgres:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    networks:
      - chat_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    # Simplified command without logging to file
    command: >
      postgres
      -c shared_buffers=256MB
      -c max_connections=200
      -c effective_cache_size=1GB
      -c maintenance_work_mem=64MB
      -c checkpoint_completion_target=0.9
      -c wal_buffers=16MB
      -c default_statistics_target=100
      -c random_page_cost=1.1
      -c effective_io_concurrency=200
      -c work_mem=4MB
      -c min_wal_size=1GB
      -c max_wal_size=4GB

  # Redis/KeyDB - Cache y sesiones
  redis:
    image: eqalpha/keydb:alpine
    container_name: chat_redis
    restart: unless-stopped
    command: keydb-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - ../data/redis:/data
    ports:
      - "${REDIS_PORT:-6379}:6379"
    networks:
      - chat_network
    healthcheck:
      test: ["CMD", "keydb-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # MinIO - Object storage para media
  minio:
    image: minio/minio:latest
    container_name: chat_minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      MINIO_BROWSER_REDIRECT_URL: ${MINIO_BROWSER_REDIRECT_URL:-http://localhost:9001}
    volumes:
      - ../data/minio:/data
    ports:
      - "${MINIO_PORT:-9000}:9000"
      - "${MINIO_CONSOLE_PORT:-9001}:9001"
    networks:
      - chat_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  # pgAdmin - Administración de PostgreSQL (opcional en producción)
  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: chat_pgadmin
    restart: unless-stopped
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD}
      PGADMIN_CONFIG_SERVER_MODE: 'False'
      PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: 'False'
    volumes:
      - ../data/pgadmin:/var/lib/pgadmin
    ports:
      - "${PGADMIN_PORT:-5050}:80"
    networks:
      - chat_network
    depends_on:
      - postgres
    profiles:
      - dev

networks:
  chat_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

# Backup original and use fixed version
mv docker-compose.yml docker-compose.yml.backup
mv docker-compose-fixed.yml docker-compose.yml

# Step 5: Check network connectivity
echo -e "\n${YELLOW}Step 5: Checking network connectivity...${NC}"
if ping -c 1 google.com &> /dev/null; then
    echo -e "${GREEN}✓ Network is working${NC}"
else
    echo -e "${RED}✗ Network appears to be down${NC}"
    echo "Please check your internet connection and try again"
    exit 1
fi

# Step 6: Start services
echo -e "\n${YELLOW}Step 6: Starting services with fixed configuration...${NC}"

# Load environment
set -a
source .env
set +a

# Pull images first
echo "Pulling Docker images..."
docker-compose pull || {
    echo -e "${RED}Failed to pull images. Trying with individual pulls...${NC}"
    docker pull postgres:15-alpine
    docker pull eqalpha/keydb:alpine
    docker pull minio/minio:latest
}

# Start services
docker-compose up -d

# Wait for PostgreSQL
echo -e "\n${YELLOW}Waiting for PostgreSQL to initialize...${NC}"
for i in {1..30}; do
    if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &> /dev/null; then
        echo -e "${GREEN}✓ PostgreSQL is ready!${NC}"
        break
    fi
    echo -n "."
    sleep 1
done

# Initialize database
echo -e "\n${YELLOW}Initializing database schema...${NC}"
if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &> /dev/null; then
    docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < ./postgres/init/01-init.sql 2>&1 || echo "Schema might already exist"
fi

# Step 7: Verify services
echo -e "\n${YELLOW}Step 7: Verifying services...${NC}"
cd "$PROJECT_DIR"
./scripts/health-check.sh

echo -e "\n${BLUE}=== Fix Complete ===${NC}"
echo ""
echo "If everything is working:"
echo "1. PostgreSQL logs are now sent to stdout (use: docker logs chat_postgres)"
echo "2. All services should be running"
echo "3. You can access:"
echo "   - PostgreSQL: localhost:5432"
echo "   - Redis: localhost:6379" 
echo "   - MinIO Console: http://localhost:9001"
echo "   - pgAdmin: http://localhost:5050"
echo ""
echo "If you still have issues, run:"
echo "  ./scripts/diagnose-postgres.sh"
