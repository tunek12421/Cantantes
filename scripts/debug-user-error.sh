#!/bin/bash

# Debug script to check user in database

echo "Checking database for user ef9106c3-b9f8-4a7d-974c-e192f9296dea..."

cd "$(dirname "$0")/../docker"

# Check if user exists in database
docker-compose exec postgres psql -U chat_user -d chat_e2ee -c "
SELECT id, phone_number, username, role, status, created_at 
FROM users 
WHERE id = 'ef9106c3-b9f8-4a7d-974c-e192f9296dea';
"

echo -e "\nChecking all users:"
docker-compose exec postgres psql -U chat_user -d chat_e2ee -c "
SELECT id, phone_number, username, role, status 
FROM users 
LIMIT 10;
"

echo -e "\nChecking user devices:"
docker-compose exec postgres psql -U chat_user -d chat_e2ee -c "
SELECT id, user_id, device_id, platform, created_at 
FROM user_devices 
WHERE user_id = 'ef9106c3-b9f8-4a7d-974c-e192f9296dea'
LIMIT 5;
"