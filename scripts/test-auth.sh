#!/bin/bash

# Test authentication flow for Chat E2EE

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Base URL
BASE_URL="http://localhost:8080/api/v1"

# Test data
PHONE_NUMBER="+1234567890"
DEVICE_ID=$(uuidgen || echo "test-device-$(date +%s)")
DEVICE_NAME="Test Device"
PUBLIC_KEY="MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA" # Mock public key

echo -e "${BLUE}=== Chat E2EE Authentication Test ===${NC}\n"

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}jq is required but not installed.${NC}"
    echo "Install with: sudo apt-get install jq"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    echo -e "${RED}curl is required but not installed.${NC}"
    exit 1
fi

# Check if server is running
echo -e "${YELLOW}1. Checking server health...${NC}"
HEALTH_RESPONSE=$(curl -s "http://localhost:8080/health")
if echo "$HEALTH_RESPONSE" | jq -r '.status' | grep -q "healthy"; then
    echo -e "${GREEN}✓ Server is healthy${NC}\n"
else
    echo -e "${RED}Server is not healthy or not running!${NC}"
    echo "Response: $HEALTH_RESPONSE"
    echo "Start the server with: docker-compose up -d backend OR ./scripts/dev.sh"
    exit 1
fi

# Request OTP
echo -e "${YELLOW}2. Requesting OTP...${NC}"
OTP_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/request-otp" \
    -H "Content-Type: application/json" \
    -d "{\"phone_number\": \"$PHONE_NUMBER\"}")

if echo "$OTP_RESPONSE" | jq -e '.message' > /dev/null; then
    echo -e "${GREEN}✓ OTP request successful${NC}"
    echo "Response: $(echo "$OTP_RESPONSE" | jq -r '.message')"
else
    echo -e "${RED}✗ OTP request failed${NC}"
    echo "$OTP_RESPONSE"
    exit 1
fi

# In development mode, the OTP is logged to console
echo -e "\n${YELLOW}Check the server logs for the OTP code${NC}"
echo "It will look like: [MOCK SMS] To: $PHONE_NUMBER, Message: Your Chat E2EE verification code is: XXXXXX"
echo -n "Enter the OTP code: "
read OTP_CODE

# Verify OTP
echo -e "\n${YELLOW}3. Verifying OTP...${NC}"
VERIFY_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/verify-otp" \
    -H "Content-Type: application/json" \
    -d "{
        \"phone_number\": \"$PHONE_NUMBER\",
        \"otp\": \"$OTP_CODE\",
        \"device_id\": \"$DEVICE_ID\",
        \"device_name\": \"$DEVICE_NAME\",
        \"public_key\": \"$PUBLIC_KEY\"
    }")

ACCESS_TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.access_token // empty')
REFRESH_TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.refresh_token // empty')
USER_ID=$(echo "$VERIFY_RESPONSE" | jq -r '.user_id // empty')
IS_NEW_USER=$(echo "$VERIFY_RESPONSE" | jq -r '.is_new_user // empty')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "null" ]; then
    echo -e "${RED}✗ OTP verification failed${NC}"
    echo "$VERIFY_RESPONSE" | jq '.'
    exit 1
fi

echo -e "${GREEN}✓ OTP verification successful${NC}"
echo "User ID: $USER_ID"
echo "New User: $IS_NEW_USER"
echo "Access Token: ${ACCESS_TOKEN:0:20}..."
echo "Refresh Token: ${REFRESH_TOKEN:0:20}..."

# Test authenticated endpoint
echo -e "\n${YELLOW}4. Testing authenticated endpoint...${NC}"
ME_RESPONSE=$(curl -s -X GET "$BASE_URL/users/me" \
    -H "Authorization: Bearer $ACCESS_TOKEN")

if echo "$ME_RESPONSE" | jq -e '.user_id' > /dev/null; then
    echo -e "${GREEN}✓ Authentication working${NC}"
    echo "$ME_RESPONSE" | jq '.'
else
    echo -e "${RED}✗ Authentication failed${NC}"
    echo "$ME_RESPONSE" | jq '.'
    exit 1
fi

# Test token refresh
echo -e "\n${YELLOW}5. Testing token refresh...${NC}"
REFRESH_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/refresh" \
    -H "Content-Type: application/json" \
    -d "{\"refresh_token\": \"$REFRESH_TOKEN\"}")

NEW_ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | jq -r '.access_token // empty')

if [ -z "$NEW_ACCESS_TOKEN" ] || [ "$NEW_ACCESS_TOKEN" = "null" ]; then
    echo -e "${RED}✗ Token refresh failed${NC}"
    echo "$REFRESH_RESPONSE" | jq '.'
    exit 1
fi

echo -e "${GREEN}✓ Token refresh successful${NC}"
echo "New Access Token: ${NEW_ACCESS_TOKEN:0:20}..."

# Test logout
echo -e "\n${YELLOW}6. Testing logout...${NC}"
LOGOUT_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/logout" \
    -H "Authorization: Bearer $NEW_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"refresh_token\": \"$REFRESH_TOKEN\"}")

if echo "$LOGOUT_RESPONSE" | jq -e '.message' > /dev/null; then
    echo -e "${GREEN}✓ Logout successful${NC}"
    echo "$LOGOUT_RESPONSE" | jq '.'
else
    echo -e "${RED}✗ Logout failed${NC}"
    echo "$LOGOUT_RESPONSE" | jq '.'
fi

# Summary
echo -e "\n${GREEN}=== All tests passed! ===${NC}"
echo -e "${BLUE}The authentication module is working correctly.${NC}"

# Save tokens for manual testing
echo -e "\n${YELLOW}Tokens saved to: /tmp/chat-e2ee-tokens.txt${NC}"
cat > /tmp/chat-e2ee-tokens.txt << EOF
# Chat E2EE Test Tokens - $(date)
ACCESS_TOKEN=$NEW_ACCESS_TOKEN
REFRESH_TOKEN=$REFRESH_TOKEN
USER_ID=$USER_ID
DEVICE_ID=$DEVICE_ID

# Example usage:
curl -H "Authorization: Bearer $NEW_ACCESS_TOKEN" $BASE_URL/users/me
EOF

echo -e "${BLUE}You can use these tokens for further testing.${NC}"