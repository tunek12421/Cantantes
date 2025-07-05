#!/bin/bash

# Check port conflicts for Chat E2EE services

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Port Availability Check ===${NC}\n"

# Function to check port
check_port() {
    local port=$1
    local service=$2
    
    echo -n "Checking port $port ($service)... "
    
    if sudo lsof -i :$port &> /dev/null; then
        echo -e "${RED}IN USE${NC}"
        echo "  Process using port:"
        sudo lsof -i :$port | grep LISTEN | head -2
        return 1
    else
        echo -e "${GREEN}AVAILABLE${NC}"
        return 0
    fi
}

# Check all required ports
PORTS_OK=0

check_port 5432 "PostgreSQL" || ((PORTS_OK++))
check_port 6379 "Redis/KeyDB" || ((PORTS_OK++))
check_port 9000 "MinIO API" || ((PORTS_OK++))
check_port 9001 "MinIO Console" || ((PORTS_OK++))
check_port 5050 "pgAdmin" || ((PORTS_OK++))

echo -e "\n${BLUE}=== Summary ===${NC}"

if [ $PORTS_OK -eq 0 ]; then
    echo -e "${GREEN}All ports are available!${NC}"
else
    echo -e "${RED}$PORTS_OK port(s) are in use${NC}"
    echo ""
    echo "Solutions:"
    echo "1. Stop conflicting services:"
    echo "   sudo systemctl stop postgresql    # For PostgreSQL"
    echo "   sudo systemctl stop redis         # For Redis"
    echo ""
    echo "2. Or change ports in docker/.env file:"
    echo "   POSTGRES_PORT=5433"
    echo "   REDIS_PORT=6380"
    echo "   etc."
fi