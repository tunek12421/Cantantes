#!/bin/bash

# Test WebSocket functionality for Chat E2EE

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Base URL
BASE_URL="http://localhost:8080"
WS_URL="ws://localhost:8080/ws"

echo -e "${BLUE}=== Chat E2EE WebSocket Test ===${NC}\n"

# Check dependencies
if ! command -v wscat &> /dev/null; then
    echo -e "${YELLOW}wscat is required but not installed.${NC}"
    echo "Install with: npm install -g wscat"
    exit 1
fi

# First, get an auth token
echo -e "${YELLOW}1. Getting authentication token...${NC}"

# Check if we have saved tokens
if [ -f "/tmp/chat-e2ee-tokens.txt" ]; then
    source /tmp/chat-e2ee-tokens.txt
    echo -e "${GREEN}Using saved token${NC}"
else
    echo -e "${RED}No saved tokens found. Run ./scripts/test-auth.sh first${NC}"
    exit 1
fi

# Test WebSocket stats endpoint
echo -e "\n${YELLOW}2. Checking WebSocket stats...${NC}"
STATS_RESPONSE=$(curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$BASE_URL/api/v1/ws/stats")

if echo "$STATS_RESPONSE" | jq -e '.websocket' > /dev/null; then
    echo -e "${GREEN}✓ WebSocket stats endpoint working${NC}"
    echo "$STATS_RESPONSE" | jq '.'
else
    echo -e "${RED}✗ WebSocket stats failed${NC}"
    echo "$STATS_RESPONSE"
fi

# Test WebSocket connection
echo -e "\n${YELLOW}3. Testing WebSocket connection...${NC}"
echo -e "${BLUE}Connecting to: $WS_URL?token=$ACCESS_TOKEN${NC}"

# Create a test message script
cat > /tmp/ws-test-messages.txt << EOF
{"type":"ping"}
{"type":"message","to":"test-user-2","payload":"SGVsbG8gZnJvbSB0ZXN0IHVzZXIh"}
{"type":"typing","to":"test-user-2","payload":"true"}
{"type":"typing","to":"test-user-2","payload":"false"}
EOF

echo -e "\n${GREEN}WebSocket Test Commands:${NC}"
echo "1. Send ping: {\"type\":\"ping\"}"
echo "2. Send message: {\"type\":\"message\",\"to\":\"USER_ID\",\"payload\":\"BASE64_ENCRYPTED_DATA\"}"
echo "3. Send typing: {\"type\":\"typing\",\"to\":\"USER_ID\",\"payload\":\"true\"}"
echo ""
echo -e "${YELLOW}Opening WebSocket connection. Type messages or Ctrl+C to exit:${NC}\n"

# Connect to WebSocket
wscat -c "$WS_URL?token=$ACCESS_TOKEN" --no-color

echo -e "\n${GREEN}WebSocket test completed!${NC}"

# Show updated stats
echo -e "\n${YELLOW}4. Final WebSocket stats:${NC}"
curl -s -H "Authorization: Bearer $ACCESS_TOKEN" "$BASE_URL/api/v1/ws/stats" | jq '.'