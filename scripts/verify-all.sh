#!/bin/bash

# Complete system verification for Chat E2EE

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Chat E2EE Complete System Verification ===${NC}\n"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Function to run check
run_check() {
    local script=$1
    local name=$2
    
    echo -e "\n${YELLOW}Running: $name${NC}"
    echo "----------------------------------------"
    
    if [ -x "$SCRIPT_DIR/$script" ]; then
        "$SCRIPT_DIR/$script"
    else
        echo -e "${RED}Script $script not found or not executable${NC}"
    fi
    
    echo "----------------------------------------"
    sleep 1
}

# Run all checks in order
run_check "check-env.sh" "Environment Variables Check"
run_check "check-ports.sh" "Port Availability Check"
run_check "health-check.sh" "Service Health Check"

# Summary
echo -e "\n${BLUE}=== Verification Summary ===${NC}"
echo ""
echo "If you see any errors above, here's what to do:"
echo ""
echo "1. ${YELLOW}Environment issues:${NC}"
echo "   ./scripts/setup-env.sh"
echo ""
echo "2. ${YELLOW}Port conflicts:${NC}"
echo "   Change ports in docker/.env or stop conflicting services"
echo ""
echo "3. ${YELLOW}Service not running:${NC}"
echo "   ./scripts/restart.sh"
echo ""
echo "4. ${YELLOW}PostgreSQL specific issues:${NC}"
echo "   ./scripts/diagnose-postgres.sh"
echo ""
echo "5. ${YELLOW}Complete reinstall:${NC}"
echo "   ./scripts/full-setup.sh"
echo ""
echo -e "${GREEN}Good luck! 🚀${NC}"