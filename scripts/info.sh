#!/bin/bash

# Quick info for Chat E2EE

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Chat E2EE - Quick Info           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}🌐 Service URLs:${NC}"
echo "  Backend API:   ${GREEN}http://localhost:8080${NC}"
echo "  MinIO Console: ${GREEN}http://localhost:9001${NC}"
echo "  PostgreSQL:    ${GREEN}localhost:5432${NC}"
echo "  Redis:         ${GREEN}localhost:6379${NC}"

echo -e "\n${YELLOW}📋 Quick Commands:${NC}"
echo "  Start:    ./scripts/start.sh"
echo "  Stop:     ./scripts/stop.sh"
echo "  Status:   ./scripts/status.sh"
echo "  Logs:     ./scripts/logs.sh -f"
echo "  Dev mode: ./scripts/dev.sh"

# Quick status check
echo -e "\n${YELLOW}📊 Current Status:${NC}"
cd "$(dirname "$0")/../docker" 2>/dev/null
if docker-compose ps 2>/dev/null | grep -q "Up"; then
    echo -e "  ${GREEN}Services are running ✓${NC}"
else
    echo -e "  ${YELLOW}Services are stopped${NC}"
    echo "  Run: ./scripts/start.sh"
fi

echo ""