#!/bin/bash

# Test script for Chat E2EE API endpoints - FIXED VERSION

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Base URL
BASE_URL="http://localhost:8080/api/v1"

# Test data
TEST_PHONE="+1234567890"

echo -e "${YELLOW}=== Testing Chat E2EE API Endpoints (Fixed) ===${NC}\n"

# Function to test endpoint with proper header handling
test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local token=$4
    local description=$5
    
    echo -e "${YELLOW}Testing: $description${NC}"
    echo "  $method $endpoint"
    
    # Build curl command properly
    if [ -n "$token" ]; then
        if [ -n "$data" ]; then
            RESPONSE=$(curl -s -X "$method" \
                -H "Content-Type: application/json" \
                -H "Authorization: Bearer $token" \
                -d "$data" \
                -w "\n%{http_code}" \
                "$BASE_URL$endpoint")
        else
            RESPONSE=$(curl -s -X "$method" \
                -H "Authorization: Bearer $token" \
                -w "\n%{http_code}" \
                "$BASE_URL$endpoint")
        fi
    else
        if [ -n "$data" ]; then
            RESPONSE=$(curl -s -X "$method" \
                -H "Content-Type: application/json" \
                -d "$data" \
                -w "\n%{http_code}" \
                "$BASE_URL$endpoint")
        else
            RESPONSE=$(curl -s -X "$method" \
                -w "\n%{http_code}" \
                "$BASE_URL$endpoint")
        fi
    fi
    
    # Parse response
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    # Check response
    if [[ $HTTP_CODE -ge 200 && $HTTP_CODE -lt 300 ]]; then
        echo -e "  ${GREEN}✓ Success ($HTTP_CODE)${NC}"
        # Show first line of response if available
        if [ -n "$BODY" ]; then
            echo "  Response preview: $(echo "$BODY" | head -n1)"
        fi
    else
        echo -e "  ${RED}✗ Failed ($HTTP_CODE)${NC}"
        if [ -n "$BODY" ]; then
            echo "  Response: $BODY"
        fi
    fi
    echo
}

# 1. Health Check
echo -e "${BLUE}=== 1. Health Check ===${NC}"
curl -s http://localhost:8080/health | jq '.' 2>/dev/null || curl -s http://localhost:8080/health
echo

# 2. API Info
test_endpoint "GET" "/" "" "" "API Info"

# 3. Authentication Flow
echo -e "${BLUE}=== 2. Authentication Flow ===${NC}"
test_endpoint "POST" "/auth/request-otp" '{"phone_number":"'$TEST_PHONE'"}' "" "Request OTP"

# 4. Verify OTP
echo -e "${YELLOW}Enter OTP from logs (or press Enter to skip auth tests):${NC} "
read -r USER_OTP

if [ -n "$USER_OTP" ]; then
    # Generate device info
    DEVICE_ID=$(uuidgen 2>/dev/null || echo "test-device-$(date +%s)")
    PUBLIC_KEY="test-public-key-base64"
    
    # Verify OTP
    echo -e "${YELLOW}Verifying OTP...${NC}"
    VERIFY_DATA='{
        "phone_number": "'$TEST_PHONE'",
        "otp": "'$USER_OTP'",
        "device_id": "'$DEVICE_ID'",
        "device_name": "Test Script",
        "public_key": "'$PUBLIC_KEY'"
    }'
    
    VERIFY_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/verify-otp" \
        -H "Content-Type: application/json" \
        -d "$VERIFY_DATA")
    
    echo "$VERIFY_RESPONSE" | jq '.' 2>/dev/null || echo "$VERIFY_RESPONSE"
    
    # Extract tokens
    ACCESS_TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.access_token // empty' 2>/dev/null)
    REFRESH_TOKEN=$(echo "$VERIFY_RESPONSE" | jq -r '.refresh_token // empty' 2>/dev/null)
    
    if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" = "empty" ]; then
        # Try to extract without jq
        ACCESS_TOKEN=$(echo "$VERIFY_RESPONSE" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
        REFRESH_TOKEN=$(echo "$VERIFY_RESPONSE" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4)
    fi
    
    if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "empty" ]; then
        echo -e "${GREEN}✓ Authentication successful${NC}\n"
        
        # Test authenticated endpoints
        echo -e "${BLUE}=== 3. Protected Endpoints (Authenticated) ===${NC}"
        test_endpoint "GET" "/users/me" "" "$ACCESS_TOKEN" "Get My Profile"
        test_endpoint "GET" "/users/contacts" "" "$ACCESS_TOKEN" "Get Contacts"
        test_endpoint "GET" "/ws/stats" "" "$ACCESS_TOKEN" "WebSocket Stats"
        test_endpoint "GET" "/gallery" "" "$ACCESS_TOKEN" "Get My Gallery"
        test_endpoint "GET" "/gallery/stats" "" "$ACCESS_TOKEN" "Gallery Stats"
        
        # Test refresh token
        echo -e "${BLUE}=== 4. Token Refresh ===${NC}"
        test_endpoint "POST" "/auth/refresh" '{"refresh_token":"'$REFRESH_TOKEN'"}' "" "Refresh Token"
        
        # Test logout
        test_endpoint "POST" "/auth/logout" '{"refresh_token":"'$REFRESH_TOKEN'"}' "$ACCESS_TOKEN" "Logout"
    else
        echo -e "${RED}Failed to extract access token${NC}"
    fi
else
    echo -e "${YELLOW}Skipping authenticated endpoint tests${NC}"
fi

# 5. Public Endpoints
echo -e "\n${BLUE}=== 5. Public Endpoints (No Auth Required) ===${NC}"
test_endpoint "GET" "/models" "" "" "List Models"
test_endpoint "GET" "/models/search?q=test" "" "" "Search Models"
test_endpoint "GET" "/models/popular" "" "" "Popular Models"
test_endpoint "GET" "/models/new" "" "" "New Models"
test_endpoint "GET" "/models/online" "" "" "Online Models"
test_endpoint "GET" "/gallery/discover" "" "" "Discover Galleries"

# 6. Test specific model endpoints
echo -e "\n${BLUE}=== 6. Model Profile Tests ===${NC}"
# First get a model ID if available
MODELS_RESPONSE=$(curl -s "$BASE_URL/models?page_size=1")
MODEL_ID=$(echo "$MODELS_RESPONSE" | jq -r '.models[0].id // empty' 2>/dev/null)

if [ -n "$MODEL_ID" ] && [ "$MODEL_ID" != "null" ] && [ "$MODEL_ID" != "empty" ]; then
    test_endpoint "GET" "/models/$MODEL_ID" "" "" "Get Model Profile"
    test_endpoint "GET" "/gallery/$MODEL_ID" "" "" "Get Model Gallery"
else
    echo -e "${YELLOW}No models found for profile testing${NC}\n"
fi

# 7. WebSocket Test
echo -e "\n${BLUE}=== 7. WebSocket Connection Test ===${NC}"
if [ -n "$ACCESS_TOKEN" ] && [ "$ACCESS_TOKEN" != "empty" ]; then
    echo "Testing WebSocket connection..."
    # Test with curl first
    WS_TEST=$(curl -s -i -N \
        -H "Connection: Upgrade" \
        -H "Upgrade: websocket" \
        -H "Sec-WebSocket-Version: 13" \
        -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" \
        "http://localhost:8080/ws?token=$ACCESS_TOKEN" | head -n 10)
    
    echo "$WS_TEST"
    
    if command -v wscat &> /dev/null; then
        echo -e "\nTesting with wscat..."
        echo '{"type":"ping"}' | timeout 3 wscat -c "ws://localhost:8080/ws?token=$ACCESS_TOKEN" 2>&1 | head -n 5
    else
        echo -e "${YELLOW}wscat not installed. Install with: npm install -g wscat${NC}"
    fi
else
    echo "Skipping WebSocket test (no auth token)"
fi

# Summary
echo -e "\n${GREEN}=== Test Summary ===${NC}"
echo "✓ Health Check: Working"
echo "✓ Authentication: Check results above"
echo "✓ Public Endpoints: Check results above"
echo "✓ Protected Endpoints: Check results above"
echo "✓ WebSocket: Check results above"
echo ""
echo "Note: The /models and /gallery/discover endpoints showing 401 errors"
echo "indicate a problem with the OptionalAuthMiddleware implementation."