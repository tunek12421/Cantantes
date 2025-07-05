#!/bin/bash

# List all project files for Chat E2EE

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}=== Chat E2EE Project Structure ===${NC}\n"

# Get project root
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

# List structure with tree if available, otherwise use find
if command -v tree &> /dev/null; then
    tree -I 'data|logs|node_modules|*.pyc|__pycache__|.git' --dirsfirst
else
    echo "Project files:"
    find . -type f \
        -not -path "./data/*" \
        -not -path "./logs/*" \
        -not -path "./.git/*" \
        -not -name "*.log" \
        -not -name "*.pyc" \
        | sort | sed 's|^\./||'
fi

echo -e "\n${GREEN}Data directories (git-ignored):${NC}"
echo "- data/postgres  (PostgreSQL data)"
echo "- data/redis     (Redis/KeyDB data)"
echo "- data/minio     (Object storage)"
echo "- logs/*         (Service logs)"

# Count files
echo -e "\n${BLUE}File Statistics:${NC}"
echo "Scripts: $(find scripts -name "*.sh" | wc -l)"
echo "Config files: $(find docker -name "*.yml" -o -name "*.conf" -o -name "*.sql" | wc -l)"
echo "Documentation: $(find . -name "*.md" | wc -l)"