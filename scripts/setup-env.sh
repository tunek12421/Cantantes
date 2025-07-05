#!/bin/bash

# Setup environment file for Chat E2EE

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Check if .env already exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}Warning: .env file already exists!${NC}"
    read -p "Do you want to backup and create a new one? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
    
    # Backup existing .env
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp .env .env.backup.$TIMESTAMP
    echo -e "${GREEN}Existing .env backed up to .env.backup.$TIMESTAMP${NC}"
fi

# Copy from example
cp .env.example .env

# Function to generate random password
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Replace all passwords
echo -e "${GREEN}Generating secure passwords...${NC}"

# Database passwords
sed -i "s/change_this_strong_password_123!/$(generate_password)/g" .env
sed -i "s/change_this_redis_password_456!/$(generate_password)/g" .env
sed -i "s/change_this_minio_password_789!/$(generate_password)/g" .env
sed -i "s/change_this_pgadmin_password!/$(generate_password)/g" .env

# JWT and encryption keys
sed -i "s/change_this_jwt_secret_key_very_long_and_random!/$(generate_password)$(generate_password)/g" .env
sed -i "s/change_this_server_encryption_key!/$(generate_password)/g" .env
sed -i "s/change_this_backup_encryption_key!/$(generate_password)/g" .env

# Set secure permissions
chmod 600 .env

echo -e "${GREEN}✓ Environment file created successfully!${NC}"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Edit docker/.env and add your Twilio credentials"
echo "2. (Optional) Add Backblaze B2 credentials for cloud backups"
echo "3. Run ./scripts/init.sh to start services"
echo
echo -e "${GREEN}File location: $(pwd)/.env${NC}"