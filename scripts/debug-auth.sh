#!/bin/bash

# Debug script for authentication issues

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Debugging Authentication Issues ===${NC}\n"

# 1. Test public endpoints WITHOUT any auth header
echo -e "${YELLOW}1. Testing public endpoints WITHOUT auth header:${NC}"

echo -e "\n${GREEN}GET /api/v1/models${NC}"
curl -v -X GET "http://localhost:8080/api/v1/models" 2>&1 | grep -E "(< HTTP|< |{)"

echo -e "\n${GREEN}GET /api/v1/gallery/discover${NC}"
curl -v -X GET "http://localhost:8080/api/v1/gallery/discover" 2>&1 | grep -E "(< HTTP|< |{)"

# 2. Test with invalid auth header
echo -e "\n${YELLOW}2. Testing public endpoints with INVALID auth header:${NC}"

echo -e "\n${GREEN}GET /api/v1/models (with invalid token)${NC}"
curl -v -X GET "http://localhost:8080/api/v1/models" \
  -H "Authorization: Bearer invalid-token-12345" 2>&1 | grep -E "(< HTTP|< |{)"

# 3. Test protected endpoints without auth
echo -e "\n${YELLOW}3. Testing PROTECTED endpoints without auth (should fail):${NC}"

echo -e "\n${GREEN}GET /api/v1/users/me${NC}"
curl -v -X GET "http://localhost:8080/api/v1/users/me" 2>&1 | grep -E "(< HTTP|< |{)"

# 4. Check registered routes
echo -e "\n${YELLOW}4. Checking debug endpoint:${NC}"
curl -s "http://localhost:8080/debug/phase5" | jq '.' 2>/dev/null || curl -s "http://localhost:8080/debug/phase5"

# 5. Direct test to see middleware chain
echo -e "\n${YELLOW}5. Testing with different Accept headers:${NC}"

echo -e "\n${GREEN}GET /api/v1/models (Accept: application/json)${NC}"
curl -s -X GET "http://localhost:8080/api/v1/models" \
  -H "Accept: application/json" \
  -w "\nHTTP Status: %{http_code}\n"

echo -e "\n${GREEN}GET /api/v1/models (no Accept header)${NC}"
curl -s -X GET "http://localhost:8080/api/v1/models" \
  -w "\nHTTP Status: %{http_code}\n"

# 6. Test raw response
echo -e "\n${YELLOW}6. Raw response from /api/v1/models:${NC}"
RESPONSE=$(curl -s -i "http://localhost:8080/api/v1/models")
echo "$RESPONSE" | head -n 20

echo -e "\n${BLUE}=== Analysis ===${NC}"
echo "If all public endpoints return 401, the OptionalAuthMiddleware is not working correctly."
echo "The middleware should allow requests WITHOUT authentication headers."
echo ""
echo "Check the backend logs to see which middleware is rejecting the requests."