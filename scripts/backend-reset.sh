#!/bin/bash

# Reset Go module for Chat E2EE backend

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== Resetting Go Module ===${NC}\n"

# Navigate to src directory
cd "$(dirname "$0")/../src"

# Remove go.sum and go.mod
echo -e "${YELLOW}Removing old module files...${NC}"
rm -f go.mod go.sum

# Re-initialize with Go 1.23
echo -e "${YELLOW}Initializing fresh module...${NC}"
go mod init chat-e2ee

# Add all dependencies one by one
echo -e "${YELLOW}Adding dependencies...${NC}"
go get github.com/gofiber/fiber/v2@latest
go get github.com/joho/godotenv@latest
go get github.com/lib/pq@latest
go get github.com/redis/go-redis/v9@latest
go get github.com/minio/minio-go/v7@v7.0.66  # Use older version compatible with Go 1.21
go get github.com/golang-jwt/jwt/v5@latest
go get github.com/olahol/melody@latest
go get github.com/twilio/twilio-go@latest
go get github.com/google/uuid@latest
go get golang.org/x/crypto@latest

# Tidy
echo -e "${YELLOW}Tidying module...${NC}"
go mod tidy

# Test build
echo -e "${YELLOW}Testing build...${NC}"
if go build -o /tmp/test-build ./cmd/server; then
    echo -e "${GREEN}✓ Build successful${NC}"
    rm /tmp/test-build
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

echo -e "\n${GREEN}Module reset complete!${NC}"