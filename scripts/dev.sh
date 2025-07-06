#!/bin/bash

# Backend development script with hot reload for Chat E2EE

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}=== Chat E2EE Backend Development ===${NC}\n"

# Check if air is installed (hot reload tool)
if ! command -v air &> /dev/null; then
    echo -e "${YELLOW}Installing air for hot reload...${NC}"
    go install github.com/cosmtrek/air@latest
fi

# Navigate to src directory
cd "$PROJECT_DIR/src"

# Check if go.mod exists
if [ ! -f "go.mod" ]; then
    echo -e "${YELLOW}Initializing Go module...${NC}"
    go mod init chat-e2ee
    go mod tidy
fi

# Create air configuration if it doesn't exist
if [ ! -f ".air.toml" ]; then
    echo -e "${YELLOW}Creating air configuration...${NC}"
    cat > .air.toml << 'EOF'
root = "."
testdata_dir = "testdata"
tmp_dir = "tmp"

[build]
  args_bin = []
  bin = "./tmp/main"
  cmd = "go build -o ./tmp/main ./cmd/server"
  delay = 1000
  exclude_dir = ["assets", "tmp", "vendor", "testdata", "logs"]
  exclude_file = []
  exclude_regex = ["_test.go"]
  exclude_unchanged = false
  follow_symlink = false
  full_bin = ""
  include_dir = []
  include_ext = ["go", "tpl", "tmpl", "html"]
  kill_delay = "0s"
  log = "build-errors.log"
  send_interrupt = false
  stop_on_error = true

[color]
  app = ""
  build = "yellow"
  main = "magenta"
  runner = "green"
  watcher = "cyan"

[log]
  time = false

[misc]
  clean_on_exit = false

[screen]
  clear_on_rebuild = false
EOF
fi

# Load environment variables
if [ -f "$PROJECT_DIR/docker/.env" ]; then
    echo -e "${GREEN}Loading environment variables...${NC}"
    set -a
    source "$PROJECT_DIR/docker/.env"
    set +a
    
    # Override some settings for local development
    export POSTGRES_HOST=localhost
    export REDIS_HOST=localhost
    export MINIO_ENDPOINT=localhost:9000
else
    echo -e "${RED}Warning: .env file not found${NC}"
fi

# Check if services are running
echo -e "\n${YELLOW}Checking required services...${NC}"

# PostgreSQL
if nc -z localhost 5432 2>/dev/null; then
    echo -e "${GREEN}✓ PostgreSQL is running${NC}"
else
    echo -e "${RED}✗ PostgreSQL is not running${NC}"
    echo "  Start it with: cd docker && docker-compose up -d postgres"
fi

# Redis
if nc -z localhost 6379 2>/dev/null; then
    echo -e "${GREEN}✓ Redis is running${NC}"
else
    echo -e "${RED}✗ Redis is not running${NC}"
    echo "  Start it with: cd docker && docker-compose up -d redis"
fi

# MinIO
if nc -z localhost 9000 2>/dev/null; then
    echo -e "${GREEN}✓ MinIO is running${NC}"
else
    echo -e "${RED}✗ MinIO is not running${NC}"
    echo "  Start it with: cd docker && docker-compose up -d minio"
fi

# Create necessary directories
mkdir -p "$PROJECT_DIR/logs/backend"
mkdir -p "$PROJECT_DIR/src/tmp"

echo -e "\n${GREEN}Starting backend with hot reload...${NC}"
echo "API will be available at: http://localhost:${APP_PORT:-8080}"
echo "Press Ctrl+C to stop"
echo ""

# Start air
air