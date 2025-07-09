#!/bin/bash

# Test script for Chat E2EE API endpoints

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Base URL
BASE_URL="http://localhost:8080/api/v1"

# Test data
TEST_PHONE="+1234567890"
TEST_OTP="123456"  # In mock mode

echo -e "${YELLOW}=== Testing Chat E2EE API Endpoints ===${NC}\n"

# Function to test endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local token=$4
    local description=$5
    
    echo -e "${YELLOW}Testing: $description${NC}"
    echo "  $method $endpoint"
    
    if [ -n "$token" ]; then
        HEADERS="-H 'Authorization: Bearer $token'"
    else
        HEADERS=""
    fi
    
    if [ -n "$data" ]; then
        RESPONSE=$(curl -s -X $method "$BASE_URL$endpoint" \
            -H "Content-Type: application/json" \
            $HEADERS \
            -d "$data" \
            -w "\n%{http_code}")
    else
        RESPONSE=$(curl -s -X $method "$BASE_URL$endpoint" \
            $HEADERS \
            -w "\n%{http_code}")
    fi
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [[ $HTTP_CODE -ge 200 && $HTTP_CODE -lt 300 ]]; then
        echo -e "  ${GREEN}✓ Success ($HTTP_CODE)${NC}"
    else
        echo -e "  ${RED}✗ Failed ($HTTP_CODE)${NC}"
        echo "  Response: $BODY"
    fi
    echo
}

# 1. Health Check
echo -e "${YELLOW}1. Health Check${NC}"
curl -s http://localhost:8080/health | jq '.' || echo "Failed"
echo

# 2. API Info
test_endpoint "GET" "/" "" "" "API Info"

# 3. Request OTP
echo -e "${YELLOW}2. Authentication Flow${NC}"
test_endpoint "POST" "/auth/request-otp" '{"phone_number":"'$TEST_PHONE'"}' "" "Request OTP"

# 4. Verify OTP (requires manual OTP from logs in dev mode)
echo -e "${YELLOW}Enter OTP from logs (or press Enter to skip auth tests):${NC} "
read -r USER_OTP

if [ -n "$USER_OTP" ]; then
    # Generate device info
    DEVICE_ID=$(uuidgen || echo "test-device-$(date +%s)")
    PUBLIC_KEY="test-public-key-base64"
    
    # Verify OTP
    VERIFY_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/verify-otp" \
        -H "Content-Type: application/json" \
        -d '{
            "phone_number": "'$TEST_PHONE'",
            "otp": "'$USER_OTP'",
            "device_id": "'$DEVICE_ID'",
            "device_name": "Test Script",
            "public_key": "'$PUBLIC_KEY'"
        }')
    
    echo "Verify OTP Response:"
    echo "$VERIFY_RESPONSE" | jq '.' || echo "$VERIFY_RESPONSE"
    
    # Extract tokens
    ACCESS_TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.access_token // empty')
    REFRESH_TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.refresh_token // empty')
    
    if [ -n "$ACCESS_TOKEN" ]; then
        echo -e "${GREEN}✓ Authentication successful${NC}\n"
        
        # Test authenticated endpoints
        echo -e "${YELLOW}3. User Endpoints (Authenticated)${NC}"
        test_endpoint "GET" "/users/me" "" "$ACCESS_TOKEN" "Get My Profile"
        test_endpoint "GET" "/users/contacts" "" "$ACCESS_TOKEN" "Get Contacts"
        
        # Test WebSocket stats
        test_endpoint "GET" "/ws/stats" "" "$ACCESS_TOKEN" "WebSocket Stats"
        
        # Test gallery
        test_endpoint "GET" "/gallery" "" "$ACCESS_TOKEN" "Get My Gallery"
    else
        echo -e "${RED}✗ Authentication failed${NC}"
    fi
else
    echo -e "${YELLOW}Skipping authenticated endpoint tests${NC}"
fi

# 5. Public Endpoints
echo -e "\n${YELLOW}4. Public Endpoints${NC}"
test_endpoint "GET" "/models" "" "" "List Models"
test_endpoint "GET" "/models/search?q=test" "" "" "Search Models"
test_endpoint "GET" "/models/popular" "" "" "Popular Models"
test_endpoint "GET" "/models/new" "" "" "New Models"
test_endpoint "GET" "/models/online" "" "" "Online Models"
test_endpoint "GET" "/gallery/discover" "" "" "Discover Galleries"

# 6. WebSocket Test
echo -e "\n${YELLOW}5. WebSocket Connection Test${NC}"
if [ -n "$ACCESS_TOKEN" ]; then
    echo "Testing WebSocket connection..."
    # Using wscat if available
    if command -v wscat &> /dev/null; then
        echo '{"type":"ping"}' | timeout 3 wscat -c "ws://localhost:8080/ws?token=$ACCESS_TOKEN" || echo "WebSocket test completed"
    else
        echo "wscat not installed. Install with: npm install -g wscat"
        echo "Manual test: ws://localhost:8080/ws?token=YOUR_TOKEN"
    fi
else
    echo "Skipping WebSocket test (no auth token)"
fi

echo -e "\n${GREEN}=== API Endpoint Testing Complete ===${NC}"
echo -e "Total endpoints tested: Check the results above"
echo -e "For full testing, implement proper test cases with a testing framework.\n"

# Summary
echo -e "${YELLOW}Key Endpoints Status:${NC}"
echo "- Health Check: Check above"
echo "- Authentication: Check above"
echo "- User Management: Check above"
echo "- Model Discovery: Check above"
echo "- WebSocket: Check above"
echo "- Media/Gallery: Requires file upload testing"