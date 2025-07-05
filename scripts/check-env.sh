#!/bin/bash

# Check environment variables for Chat E2EE

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Environment Variables Check ===${NC}\n"

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Check if .env exists
if [ ! -f ".env" ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Run: ./scripts/setup-env.sh"
    exit 1
fi

# Load environment variables
set -a
source .env
set +a

# Function to check variable
check_var() {
    local var_name=$1
    local var_value=${!var_name}
    local is_secret=$2
    
    if [ -z "$var_value" ]; then
        echo -e "${RED}✗ $var_name${NC} - Not set"
        return 1
    else
        if [ "$is_secret" = "true" ]; then
            echo -e "${GREEN}✓ $var_name${NC} - Set (hidden)"
        else
            echo -e "${GREEN}✓ $var_name${NC} - $var_value"
        fi
        return 0
    fi
}

# Check critical variables
echo -e "${YELLOW}Database Configuration:${NC}"
check_var "POSTGRES_DB" false
check_var "POSTGRES_USER" false
check_var "POSTGRES_PASSWORD" true
check_var "POSTGRES_PORT" false

echo -e "\n${YELLOW}Redis Configuration:${NC}"
check_var "REDIS_PORT" false
check_var "REDIS_PASSWORD" true

echo -e "\n${YELLOW}MinIO Configuration:${NC}"
check_var "MINIO_ROOT_USER" false
check_var "MINIO_ROOT_PASSWORD" true
check_var "MINIO_PORT" false
check_var "MINIO_CONSOLE_PORT" false

echo -e "\n${YELLOW}Application Configuration:${NC}"
check_var "APP_ENV" false
check_var "JWT_SECRET" true

echo -e "\n${YELLOW}Optional Services:${NC}"
check_var "TWILIO_ACCOUNT_SID" false
check_var "TWILIO_AUTH_TOKEN" true
check_var "B2_ACCOUNT_ID" false

# Check for common issues
echo -e "\n${BLUE}=== Common Issues Check ===${NC}"

# Check for spaces in passwords
if grep -E "PASSWORD=.*[[:space:]]" .env | grep -v "^#"; then
    echo -e "${RED}⚠ Warning: Found spaces in password values${NC}"
fi

# Check for default values
if grep -q "change_this" .env; then
    echo -e "${RED}⚠ Warning: Found unchanged default values${NC}"
    grep "change_this" .env | grep -v "^#" | cut -d'=' -f1
fi

# Check for empty values
echo -e "\n${YELLOW}Checking for empty values:${NC}"
while IFS='=' read -r key value; do
    # Skip comments and empty lines
    if [[ ! "$key" =~ ^[[:space:]]*# ]] && [[ -n "$key" ]]; then
        if [ -z "$value" ]; then
            echo -e "${RED}✗ $key is empty${NC}"
        fi
    fi
done < .env

# Check file permissions
PERM=$(stat -c "%a" .env)
if [ "$PERM" != "600" ]; then
    echo -e "${YELLOW}⚠ Warning: .env has permissions $PERM (should be 600)${NC}"
    echo "  Fix with: chmod 600 docker/.env"
fi

echo -e "\n${BLUE}=== Summary ===${NC}"
echo "If any critical variables are missing, run:"
echo "  ./scripts/setup-env.sh"
echo ""
echo "To edit the configuration:"
echo "  nano docker/.env"