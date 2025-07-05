#!/bin/bash

# Diagnose PostgreSQL issues for Chat E2EE

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== PostgreSQL Diagnostic Tool ===${NC}\n"

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Load environment variables
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

# Check if container is running
echo -e "${YELLOW}1. Checking container status...${NC}"
if docker ps | grep -q chat_postgres; then
    echo -e "${GREEN}✓ Container is running${NC}"
else
    echo -e "${RED}✗ Container is not running${NC}"
    echo "Trying to start it..."
    docker-compose up -d postgres
    sleep 5
fi

# Check container logs
echo -e "\n${YELLOW}2. Recent PostgreSQL logs:${NC}"
docker-compose logs --tail=30 postgres | grep -E "(ERROR|FATAL|WARNING|ready|started|database system is ready)" || docker-compose logs --tail=30 postgres

# Check PostgreSQL process
echo -e "\n${YELLOW}3. PostgreSQL process status:${NC}"
docker-compose exec -T postgres ps aux | grep postgres || echo "Process check failed"

# Try to connect
echo -e "\n${YELLOW}4. Testing PostgreSQL connection:${NC}"
echo "Database: $POSTGRES_DB"
echo "User: $POSTGRES_USER"
echo "Port: ${POSTGRES_PORT:-5432}"

# Test with pg_isready
echo -e "\n${YELLOW}Testing with pg_isready:${NC}"
if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" 2>&1; then
    echo -e "${GREEN}✓ pg_isready check passed${NC}"
else
    echo -e "${RED}✗ pg_isready check failed${NC}"
    
    # Try without database name
    echo "Trying without database name..."
    if docker-compose exec -T postgres pg_isready -U "$POSTGRES_USER" 2>&1; then
        echo "Connection works but database might not exist"
    fi
fi

# Test actual connection
echo -e "\n${YELLOW}5. Testing actual database connection:${NC}"
if docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT version();" 2>&1; then
    echo -e "${GREEN}✓ Database connection successful${NC}"
else
    echo -e "${RED}✗ Database connection failed${NC}"
fi

# Check disk space
echo -e "\n${YELLOW}6. Checking disk space:${NC}"
df -h $(pwd)/..

# Check permissions
echo -e "\n${YELLOW}7. Checking data directory permissions:${NC}"
ls -la ../data/postgres/ | head -5 || echo "Cannot read postgres data directory"

# Memory check
echo -e "\n${YELLOW}8. Container resource usage:${NC}"
docker stats --no-stream chat_postgres

# Check if initialization completed
echo -e "\n${YELLOW}9. Checking if database was initialized:${NC}"
if docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt" 2>&1 | grep -q "users"; then
    echo -e "${GREEN}✓ Database tables exist${NC}"
else
    echo -e "${YELLOW}! Database might not be initialized${NC}"
    echo "Running initialization script..."
    docker-compose exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" < ./postgres/init/01-init.sql 2>&1 || echo "Init failed"
fi

echo -e "\n${BLUE}=== Diagnostic Summary ===${NC}"

# Check for common PostgreSQL errors
if docker-compose logs postgres 2>&1 | grep -q "FATAL:  password authentication failed"; then
    echo -e "${RED}Authentication Error:${NC} Password mismatch"
    echo "Solution: Recreate container with: ./scripts/restart.sh --clean"
elif docker-compose logs postgres 2>&1 | grep -q "FATAL:  database.*does not exist"; then
    echo -e "${RED}Database Error:${NC} Database not created"
    echo "Solution: Create database manually or check POSTGRES_DB in .env"
elif docker-compose logs postgres 2>&1 | grep -q "could not bind"; then
    echo -e "${RED}Port Error:${NC} Port 5432 already in use"
    echo "Solution: Stop other PostgreSQL or change port in .env"
fi

echo ""
echo "If PostgreSQL is still not working, try:"
echo "1. ./scripts/restart.sh --clean  (WARNING: deletes data)"
echo "2. Check if port 5432 is already in use: sudo lsof -i :5432"
echo "3. Remove and recreate the container: cd docker && docker-compose down && docker-compose up -d"
echo "4. Check Docker daemon logs: sudo journalctl -u docker.service"
echo "5. Full reinstall: ./scripts/full-setup.sh"