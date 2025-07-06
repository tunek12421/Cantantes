#!/bin/bash

# Chat E2EE - Initialization Script
# This script sets up the development environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   log_error "This script should not be run as root!"
   exit 1
fi

log_info "Starting Chat E2EE initialization..."

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    log_error "Docker is not installed!"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    log_error "Docker Compose is not installed!"
    exit 1
fi

# Create .env file if it doesn't exist
if [ ! -f "docker/.env" ]; then
    log_info "Creating .env file from template..."
    cp docker/.env.example docker/.env
    
    # Generate secure passwords
    log_info "Generating secure passwords..."
    
    # Function to generate random password
    generate_password() {
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
    }
    
    # Update passwords in .env
    sed -i "s/change_this_strong_password_123!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_redis_password_456!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_minio_password_789!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_pgadmin_password!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_jwt_secret_key_very_long_and_random!/$(generate_password)$(generate_password)/g" docker/.env
    sed -i "s/change_this_server_encryption_key!/$(generate_password)/g" docker/.env
    sed -i "s/change_this_backup_encryption_key!/$(generate_password)/g" docker/.env
    
    log_warn "Generated secure passwords in .env file. Please update SMS provider credentials!"
else
    log_info ".env file already exists, skipping..."
fi

# Set proper permissions
log_info "Setting directory permissions..."
chmod 755 scripts/*.sh
chmod 600 docker/.env

# Create necessary directories if they don't exist
log_info "Creating data directories..."
mkdir -p data/{postgres,redis,minio,pgadmin}
mkdir -p logs/{postgres,redis,minio}

# Set ownership for data directories
log_info "Setting directory ownership..."
sudo chown -R 999:999 data/postgres || true
sudo chown -R 999:999 data/redis || true
sudo chown -R 1000:1000 data/minio || true

# Start services
log_info "Starting Docker services..."
cd docker

# Load environment variables
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
    log_info "Environment variables loaded"
else
    log_error ".env file not found in docker directory!"
    exit 1
fi

# Pull images first
log_info "Pulling Docker images..."
docker-compose pull

# Start services
docker-compose up -d

# Wait for services to be ready
log_info "Waiting for services to be ready..."

# Wait for PostgreSQL specifically (it takes longer)
log_info "Waiting for PostgreSQL to initialize (this may take up to 30 seconds on first run)..."
for i in {1..30}; do
    if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &> /dev/null; then
        break
    fi
    echo -n "."
    sleep 1
done
echo ""

# Check service health
log_info "Checking service health..."

# PostgreSQL
if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" &> /dev/null; then
    log_info "PostgreSQL is ready ✓"
    # Run init script if tables don't exist
    if ! docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt" 2>&1 | grep -q "users"; then
        log_info "Initializing database schema..."
        if docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < ./postgres/init/01-init.sql; then
            log_info "Database schema initialized successfully"
        else
            log_warn "Database initialization had some warnings (this is normal on re-runs)"
        fi
    fi
else
    log_error "PostgreSQL is not ready ✗"
    log_warn "This is normal on first run. Try running ./scripts/health-check.sh in a minute"
    log_warn "Or check logs with: ./scripts/logs.sh postgres"
fi

# Redis
if [ -n "$REDIS_PASSWORD" ]; then
    if docker-compose exec -T redis keydb-cli -a "$REDIS_PASSWORD" ping &> /dev/null; then
        log_info "Redis/KeyDB is ready ✓"
    else
        log_error "Redis/KeyDB is not ready ✗"
    fi
else
    if docker-compose exec -T redis keydb-cli ping &> /dev/null; then
        log_info "Redis/KeyDB is ready ✓"
    else
        log_error "Redis/KeyDB is not ready ✗"
    fi
fi

# MinIO
if curl -s http://localhost:9000/minio/health/live &> /dev/null; then
    log_info "MinIO is ready ✓"
else
    log_error "MinIO is not ready ✗"
fi

# Create MinIO buckets
log_info "Setting up MinIO buckets..."

# Wait a bit more for MinIO to be fully ready
sleep 5

# Get MinIO credentials from environment
MINIO_USER="${MINIO_ROOT_USER}"
MINIO_PASS="${MINIO_ROOT_PASSWORD}"

# Configure MinIO client
docker-compose exec -T minio mc alias set local http://localhost:9000 "$MINIO_USER" "$MINIO_PASS" || {
    log_error "Failed to configure MinIO client. Please check MinIO credentials."
    exit 1
}

# Create buckets
docker-compose exec -T minio mc mb local/chat-media --ignore-existing || true
docker-compose exec -T minio mc mb local/chat-thumbnails --ignore-existing || true
docker-compose exec -T minio mc mb local/chat-temp --ignore-existing || true

# Set bucket policies
docker-compose exec -T minio mc anonymous set download local/chat-media || true
docker-compose exec -T minio mc anonymous set download local/chat-thumbnails || true

# Show service URLs
echo -e "\n${GREEN}=== Services are ready! ===${NC}"
echo -e "PostgreSQL:    ${GREEN}localhost:5432${NC}"
echo -e "Redis/KeyDB:   ${GREEN}localhost:6379${NC}"
echo -e "MinIO API:     ${GREEN}http://localhost:9000${NC}"
echo -e "MinIO Console: ${GREEN}http://localhost:9001${NC}"

if grep -q "APP_ENV=development" .env; then
    echo -e "pgAdmin:       ${GREEN}http://localhost:5050${NC}"
fi

# Backend Go (si existe el Dockerfile)
if [ -f "./backend/Dockerfile" ]; then
    log_info "Building and starting Go backend..."
    docker-compose build backend
    docker-compose up -d backend
    
    # Esperar al backend
    for i in {1..30}; do
        if curl -s http://localhost:${APP_PORT:-8080}/health &> /dev/null; then
            log_info "Backend API is ready ✓"
            break
        fi
        sleep 1
    done
fi

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Update SMS provider credentials in docker/.env"
echo "   nano docker/.env"
echo "2. Configure your domain and SSL certificates"
echo "3. Start developing the Go backend!"
echo ""
echo "Useful commands:"
echo "  ./scripts/health-check.sh  - Check service status"
echo "  ./scripts/logs.sh postgres - View PostgreSQL logs"
echo "  ./scripts/psql.sh         - Access PostgreSQL"
echo "  ./scripts/info.sh         - Project information"
echo ""
log_info "Initialization complete! 🚀"