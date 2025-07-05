#!/bin/bash

# Quick project info for Chat E2EE

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Chat E2EE - Project Info           ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"

echo -e "\n${CYAN}📋 Project:${NC} Private Chat Platform with E2EE"
echo -e "${CYAN}🎯 Goal:${NC} 2,000 → 33,000 users in 12 months"
echo -e "${CYAN}💰 Budget:${NC} ~$58 USD/month"
echo -e "${CYAN}⏱️  Timeline:${NC} 7-day MVP"

echo -e "\n${YELLOW}🚀 Quick Commands:${NC}"
echo "  Start all:     cd docker && docker-compose up -d"
echo "  Check health:  ./scripts/health-check.sh"
echo "  View logs:     ./scripts/logs.sh [service]"
echo "  Access DB:     ./scripts/psql.sh"

echo -e "\n${YELLOW}🌐 Service URLs:${NC}"
echo "  MinIO Console: ${GREEN}http://localhost:9001${NC}"
echo "  pgAdmin:       ${GREEN}http://localhost:5050${NC}"
echo "  PostgreSQL:    ${GREEN}localhost:5432${NC}"
echo "  Redis:         ${GREEN}localhost:6379${NC}"

# Quick status check
echo -e "\n${YELLOW}📊 Current Status:${NC}"
cd "$(dirname "$0")/../docker"
if docker-compose ps 2>/dev/null | grep -q "Up"; then
    echo -e "  Services: ${GREEN}Running ✓${NC}"
    docker-compose ps --format "table {{.Service}}\t{{.Status}}" | grep -E "(SERVICE|postgres|redis|minio)" | sed 's/^/  /'
else
    echo -e "  Services: ${YELLOW}Not running${NC}"
    echo "  Run: ./scripts/init.sh"
fi

echo -e "\n${CYAN}📚 Documentation:${NC} README.md"
echo -e "${CYAN}🛠️  Next step:${NC} Start building the Go backend!"
echo ""