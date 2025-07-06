#!/bin/bash

# Initialize Go backend for Chat E2EE

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Initializing Chat E2EE Backend ===${NC}\n"

# Navigate to src directory
cd "$(dirname "$0")/../src"

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Go is not installed!${NC}"
    echo "Please install Go 1.23 or later from https://golang.org/dl/"
    exit 1
fi

# Check Go version
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
REQUIRED_VERSION="1.23"

if ! printf '%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V | head -n1 | grep -q "$REQUIRED_VERSION"; then
    echo -e "${RED}Go version $GO_VERSION is too old!${NC}"
    echo "Please install Go 1.23 or later from https://golang.org/dl/"
    exit 1
fi

echo -e "${YELLOW}Go version:${NC}"
go version

# Initialize go module if needed
if [ ! -f "go.mod" ]; then
    echo -e "\n${YELLOW}Initializing Go module...${NC}"
    go mod init chat-e2ee
fi

# Download dependencies
echo -e "\n${YELLOW}Downloading dependencies...${NC}"
go mod download

# Install missing dependencies explicitly
echo -e "\n${YELLOW}Installing missing dependencies...${NC}"
go get github.com/lib/pq
go get github.com/redis/go-redis/v9
go get github.com/minio/minio-go/v7
go get github.com/minio/minio-go/v7/pkg/credentials
go get github.com/gofiber/fiber/v2
go get github.com/joho/godotenv
go get github.com/golang-jwt/jwt/v5
go get github.com/olahol/melody
go get github.com/twilio/twilio-go
go get github.com/google/uuid
go get golang.org/x/crypto

# Tidy up and create go.sum
echo -e "\n${YELLOW}Tidying dependencies...${NC}"
go mod tidy

# Verify
if [ -f "go.sum" ]; then
    echo -e "\n${GREEN}✓ go.sum created successfully${NC}"
else
    echo -e "\n${RED}✗ Failed to create go.sum${NC}"
    exit 1
fi

# Test build
echo -e "\n${YELLOW}Testing build...${NC}"
if go build -o /tmp/test-build ./cmd/server; then
    echo -e "${GREEN}✓ Build successful${NC}"
    rm /tmp/test-build
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

echo -e "\n${GREEN}Backend initialization complete!${NC}"
echo -e "${YELLOW}You can now run:${NC}"
echo "  ./scripts/backend-start.sh    # Start with Docker"
echo "  ./scripts/backend-dev.sh      # Development mode"