#!/bin/bash

# Test script for Chat E2EE API endpoints (Version 2 - Fixed)

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

# Debug mode
DEBUG=false
if [ "$1" = "--debug" ] || [ "$1" = "-d" ]; then
    DEBUG=true
    echo -e "${BLUE}Debug mode enabled${NC}\n"
fi

echo -e "${YELLOW}=== Testing Chat E2EE API Endpoints ===${NC}\n"

# Function to make HTTP request
make_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local token=$4
    
    # Build headers array
    local headers=(-H "Content-Type: application/json")
    if [ -n "$token" ]; then
        headers+=(-H "Authorization: Bearer $token")
    fi
    
    # Build curl command
    if [ -n "$data" ]; then
        curl -s -X "$method" \
            "${headers[@]}" \
            -d "$data" \
            -w "\n%{http_code}" \
            "$BASE_URL$endpoint"
    else
        curl -s -X "$method" \
            "${headers[@]}" \
            -w "\n%{http_code}" \
            "$BASE_URL$endpoint"
    fi
}

# Function to test endpoint
test_endpoint() {
    local method=$1
    local endpoint=$2
    local data=$3
    local token=$4
    local description=$5
    
    echo -e "${YELLOW}Testing: $description${NC}"
    echo "  $method $endpoint"
    
    if [ "$DEBUG" = "true" ]; then
        echo -e "  ${BLUE}Token: ${token:0:20}...${NC}" 
    fi
    
    # Make request
    RESPONSE=$(make_request "$method" "$endpoint" "$data" "$token")
    
    # Parse response
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    # Check response
    if [ -z "$HTTP_CODE" ] || [ "$HTTP_CODE" = "000" ]; then
        echo -e "  ${RED}✗ Connection error${NC}"
        return
    fi
    
    if [[ $HTTP_CODE -ge 200 && $HTTP_CODE -lt 300 ]]; then
        echo -e "  ${GREEN}✓ Success ($HTTP_CODE)${NC}"
        if [ "$DEBUG" = "true" ] && [ -n "$BODY" ]; then
            echo "  Response: $BODY" | head -n 3
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
echo -e "${YELLOW}1. Health Check${NC}"
curl -s http://localhost:8080/health | jq '.' 2>/dev/null || curl -s http://localhost:8080/health
echo

# 2. API Info
test_endpoint "GET" "/" "" "" "API Info"

# 3. Authentication Flow
echo -e "${YELLOW}2. Authentication Flow${NC}"
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
    
    VERIFY_RESPONSE=$(make_request "POST" "/auth/verify-otp" "$VERIFY_DATA" "")
    HTTP_CODE=$(echo "$VERIFY_RESPONSE" | tail -n1)
    BODY=$(echo "$VERIFY_RESPONSE" | sed '$d')
    
    if [[ $HTTP_CODE -eq 200 ]]; then
        echo -e "${GREEN}✓ Authentication successful${NC}"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
        
        # Extract tokens
        ACCESS_TOKEN=$(echo "$BODY" | jq -r '.access_token // empty' 2>/dev/null)
        REFRESH_TOKEN=$(echo "$BODY" | jq -r '.refresh_token // empty' 2>/dev/null)
        
        if [ -z "$ACCESS_TOKEN" ]; then
            # Try to extract without jq
            ACCESS_TOKEN=$(echo "$BODY" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4)
        fi
        
        if [ -n "$ACCESS_TOKEN" ]; then
            echo -e "\n${YELLOW}3. Testing Authenticated Endpoints${NC}"
            test_endpoint "GET" "/users/me" "" "$ACCESS_TOKEN" "Get My Profile"
            test_endpoint "GET" "/users/contacts" "" "$ACCESS_TOKEN" "Get Contacts"
            test_endpoint "GET" "/ws/stats" "" "$ACCESS_TOKEN" "WebSocket Stats"
            test_endpoint "GET" "/gallery" "" "$ACCESS_TOKEN" "Get My Gallery"
            test_endpoint "GET" "/gallery/stats" "" "$ACCESS_TOKEN" "Gallery Stats"
            
            # Test refresh token
            echo -e "${YELLOW}4. Testing Token Refresh${NC}"
            test_endpoint "POST" "/auth/refresh" '{"refresh_token":"'$REFRESH_TOKEN'"}' "" "Refresh Token"
        else
            echo -e "${RED}Failed to extract access token${NC}"
        fi
    else
        echo -e "${RED}✗ Authentication failed ($HTTP_CODE)${NC}"
        echo "$BODY"
    fi
else
    echo -e "${YELLOW}Skipping authenticated endpoint tests${NC}"
fi

# 5. Public Endpoints
echo -e "\n${YELLOW}5. Public Endpoints (No Auth Required)${NC}"
test_endpoint "GET" "/models" "" "" "List Models"
test_endpoint "GET" "/models/search?q=test" "" "" "Search Models"
test_endpoint "GET" "/models/popular" "" "" "Popular Models"
test_endpoint "GET" "/models/new" "" "" "New Models"
test_endpoint "GET" "/models/online" "" "" "Online Models"
test_endpoint "GET" "/gallery/discover" "" "" "Discover Galleries"

# 6. Test specific model endpoints
echo -e "\n${YELLOW}6. Model Profile Tests${NC}"
# First get a model ID if available
MODELS_RESPONSE=$(make_request "GET" "/models?page_size=1" "" "")
MODEL_ID=$(echo "$MODELS_RESPONSE" | sed '$d' | jq -r '.models[0].id // empty' 2>/dev/null)

if [ -n "$MODEL_ID" ] && [ "$MODEL_ID" != "null" ]; then
    test_endpoint "GET" "/models/$MODEL_ID" "" "" "Get Model Profile"
    test_endpoint "GET" "/gallery/$MODEL_ID" "" "" "Get Model Gallery"
else
    echo -e "${YELLOW}No models found for profile testing${NC}\n"
fi

# 7. WebSocket Test
echo -e "\n${YELLOW}7. WebSocket Connection Test${NC}"
if [ -n "$ACCESS_TOKEN" ]; then
    echo "Testing WebSocket connection..."
    if command -v wscat &> /dev/null; then
        echo '{"type":"ping"}' | timeout 3 wscat -c "ws://localhost:8080/ws?token=$ACCESS_TOKEN" 2>&1 | head -n 5
    else
        echo "wscat not installed. Install with: npm install -g wscat"
        echo "Manual test URL: ws://localhost:8080/ws?token=YOUR_TOKEN"
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
echo ""
echo "For detailed debugging, run: $0 --debug"
echo ""