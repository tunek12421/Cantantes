#!/bin/bash

# Restore complete docker-compose.yml with backend service

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Restoring Complete Docker Compose Configuration ===${NC}\n"

# Navigate to docker directory
cd "$(dirname "$0")/../docker"

# Backup current docker-compose.yml
cp docker-compose.yml docker-compose-minimal.yml

# Create complete docker-compose.yml with backend service
cat > docker-compose.yml << 'EOF'
services:
  # PostgreSQL - Base de datos principal
  postgres:
    image: postgres:15-alpine
    container_name: chat_postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - ./postgres/init:/docker-entrypoint-initdb.d
      - ../data/postgres:/var/lib/postgresql/data
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    networks:
      - chat_network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    # Simplified command without logging to file
    command: >
      postgres
      -c shared_buffers=256MB
      -c max_connections=200
      -c effective_cache_size=1GB
      -c maintenance_work_mem=64MB
      -c checkpoint_completion_target=0.9
      -c wal_buffers=16MB
      -c default_statistics_target=100
      -c random_page_cost=1.1
      -c effective_io_concurrency=200
      -c work_mem=4MB
      -c min_wal_size=1GB
      -c max_wal_size=4GB

  # Redis/KeyDB - Cache y sesiones
  redis:
    image: eqalpha/keydb:alpine
    container_name: chat_redis
    restart: unless-stopped
    command: keydb-server --requirepass ${REDIS_PASSWORD}
    volumes:
      - ../data/redis:/data
    ports:
      - "${REDIS_PORT:-6379}:6379"
    networks:
      - chat_network
    healthcheck:
      test: ["CMD", "keydb-cli", "-a", "${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  # MinIO - Object storage para media
  minio:
    image: minio/minio:latest
    container_name: chat_minio
    restart: unless-stopped
    command: server /data --console-address ":9001"
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      MINIO_BROWSER_REDIRECT_URL: ${MINIO_BROWSER_REDIRECT_URL:-http://localhost:9001}
    volumes:
      - ../data/minio:/data
    ports:
      - "${MINIO_PORT:-9000}:9000"
      - "${MINIO_CONSOLE_PORT:-9001}:9001"
    networks:
      - chat_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  # Backend Go - API y WebSocket
  backend:
    build:
      context: ..
      dockerfile: docker/backend/Dockerfile
    container_name: chat_backend
    restart: unless-stopped
    environment:
      # App
      APP_ENV: ${APP_ENV}
      APP_PORT: ${APP_PORT:-8080}
      APP_DEBUG: ${APP_DEBUG:-false}
      CORS_ORIGINS: ${CORS_ORIGINS:-http://localhost:3000}
      
      # Database
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
      
      # Redis
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
      
      # MinIO
      MINIO_ENDPOINT: minio:9000
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
      
      # JWT
      JWT_SECRET: ${JWT_SECRET}
      JWT_ACCESS_TOKEN_EXPIRE: ${JWT_ACCESS_TOKEN_EXPIRE:-15m}
      JWT_REFRESH_TOKEN_EXPIRE: ${JWT_REFRESH_TOKEN_EXPIRE:-7d}
      
      # SMS
      SMS_PROVIDER: ${SMS_PROVIDER:-mock}
      TWILIO_ACCOUNT_SID: ${TWILIO_ACCOUNT_SID}
      TWILIO_AUTH_TOKEN: ${TWILIO_AUTH_TOKEN}
      TWILIO_PHONE_NUMBER: ${TWILIO_PHONE_NUMBER}
      
      # Rate Limiting
      RATE_LIMIT_REQUESTS: ${RATE_LIMIT_REQUESTS:-100}
      RATE_LIMIT_WINDOW: ${RATE_LIMIT_WINDOW:-1m}
    volumes:
      - ../logs/backend:/app/logs
    ports:
      - "${APP_PORT:-8080}:8080"
    networks:
      - chat_network
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      minio:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  # pgAdmin - Administración de PostgreSQL (opcional en producción)
  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: chat_pgadmin
    restart: unless-stopped
    environment:
      PGADMIN_DEFAULT_EMAIL: ${PGADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: ${PGADMIN_PASSWORD}
      PGADMIN_CONFIG_SERVER_MODE: 'False'
      PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: 'False'
    volumes:
      - ../data/pgadmin:/var/lib/pgadmin
    ports:
      - "${PGADMIN_PORT:-5050}:80"
    networks:
      - chat_network
    depends_on:
      - postgres
    profiles:
      - dev

networks:
  chat_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
EOF

echo -e "${GREEN}✓ docker-compose.yml restored with backend service${NC}"

# Verify the file
if grep -q "backend:" docker-compose.yml; then
    echo -e "${GREEN}✓ Backend service definition confirmed${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Backend service might not be properly defined${NC}"
fi

echo -e "\n${YELLOW}Now you can run:${NC}"
echo "  ./scripts/backend-start.sh"