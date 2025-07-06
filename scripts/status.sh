#!/bin/bash

# Health check script for Chat E2EE services

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Status icons
CHECK="✓"
CROSS="✗"
WARN="!"

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}${CROSS} docker-compose not found${NC}"
    exit 1
fi

cd "$(dirname "$0")/../docker"

echo -e "${BLUE}=== Chat E2EE Service Health Check ===${NC}\n"

# Function to check service
check_service() {
    local service=$1
    local check_command=$2
    local port=$3
    
    # Check if container is running
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "chat_${service}.*Up"; then
        # Execute health check command
        if eval "$check_command" &> /dev/null; then
            echo -e "${GREEN}${CHECK} ${service}${NC} - Running on port ${port}"
            return 0
        else
            echo -e "${YELLOW}${WARN} ${service}${NC} - Container up but service not responding"
            return 1
        fi
    else
        echo -e "${RED}${CROSS} ${service}${NC} - Container not running"
        return 1
    fi
}

# Load environment for credentials
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

# Check services with proper credentials
if [ -n "$POSTGRES_USER" ] && [ -n "$POSTGRES_DB" ]; then
    check_service "postgres" "docker-compose exec -T postgres pg_isready -U '$POSTGRES_USER' -d '$POSTGRES_DB'" "5432"
else
    check_service "postgres" "docker-compose exec -T postgres pg_isready" "5432"
fi
POSTGRES_OK=$?

# Redis check with authentication
if [ -n "$REDIS_PASSWORD" ]; then
    check_service "redis" "docker-compose exec -T redis keydb-cli -a '$REDIS_PASSWORD' ping" "6379"
else
    check_service "redis" "docker-compose exec -T redis keydb-cli ping" "6379"
fi
REDIS_OK=$?

check_service "minio" "curl -s http://localhost:9000/minio/health/live" "9000/9001"
MINIO_OK=$?

# Check disk space
echo -e "\n${BLUE}=== Disk Usage ===${NC}"
df -h | grep -E "(Filesystem|$(pwd | cut -d'/' -f1-3))" | awk '{printf "%-20s %s\n", $1, $5}'

# Check memory usage
echo -e "\n${BLUE}=== Memory Usage ===${NC}"
docker stats --no-stream --format "table {{.Container}}\t{{.MemUsage}}\t{{.MemPerc}}" chat_postgres chat_redis chat_minio 2>/dev/null || echo "Unable to get stats"

# Check data directory sizes
echo -e "\n${BLUE}=== Data Directory Sizes ===${NC}"
if [ -d "../data" ]; then
    du -sh ../data/* 2>/dev/null | sort -h
else
    echo "Data directory not found"
fi

# Check logs for errors
echo -e "\n${BLUE}=== Recent Errors (last 24h) ===${NC}"
for service in postgres redis minio; do
    echo -e "\n${YELLOW}${service}:${NC}"
    docker-compose logs --tail=100 $service 2>&1 | grep -i -E "(error|fail|crash)" | tail -5 || echo "No errors found"
done

# Summary
echo -e "\n${BLUE}=== Summary ===${NC}"
TOTAL=$((POSTGRES_OK + REDIS_OK + MINIO_OK))

if [ $TOTAL -eq 0 ]; then
    echo -e "${GREEN}All services are healthy! ${CHECK}${NC}"
    exit 0
else
    echo -e "${RED}Some services are not healthy. Please check logs.${NC}"
    exit 1
fi


# Check services with proper credentials
if [ -n "$POSTGRES_USER" ] && [ -n "$POSTGRES_DB" ]; then
    check_service "postgres" "docker-compose exec -T postgres pg_isready -U '$POSTGRES_USER' -d '$POSTGRES_DB'" "5432"
else
    check_service "postgres" "docker-compose exec -T postgres pg_isready" "5432"
fi
POSTGRES_OK=$?

# Redis check with authentication
if [ -n "$REDIS_PASSWORD" ]; then
    check_service "redis" "docker-compose exec -T redis keydb-cli -a '$REDIS_PASSWORD' ping" "6379"
else
    check_service "redis" "docker-compose exec -T redis keydb-cli ping" "6379"
fi
REDIS_OK=$?

check_service "minio" "curl -s http://localhost:9000/minio/health/live" "9000/9001"
MINIO_OK=$?

# Check backend if running
if docker ps --format "{{.Names}}" | grep -q "chat_backend"; then
    check_service "backend" "curl -s http://localhost:8080/health" "8080"
    BACKEND_OK=$?
else
    echo -e "${YELLOW}! backend${NC} - Not started (run ./scripts/backend-start.sh to start)"
    BACKEND_OK=0  # Don't count as error if not started
fi