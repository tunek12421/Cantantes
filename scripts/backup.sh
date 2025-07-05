#!/bin/bash

# Backup script for Chat E2EE
# Creates encrypted backups of PostgreSQL and MinIO data

set -e

# Configuration
BACKUP_DIR="/home/$(whoami)/backups/chat-e2ee"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=7

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment variables
ENV_FILE="$(dirname "$0")/../docker/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
    exit 1
fi

# Functions
log_info() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Create backup directory
mkdir -p "$BACKUP_DIR"/{postgres,minio,logs}

cd "$(dirname "$0")/../docker"

log_info "Starting backup process..."

# Backup PostgreSQL
log_info "Backing up PostgreSQL database..."
if docker-compose exec -T postgres pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | \
   gzip | \
   openssl enc -aes-256-cbc -salt -pass pass:"$BACKUP_ENCRYPTION_KEY" \
   > "$BACKUP_DIR/postgres/db_${TIMESTAMP}.sql.gz.enc"; then
    log_info "PostgreSQL backup completed"
else
    log_error "PostgreSQL backup failed"
    exit 1
fi

# Backup MinIO data (only media, not temp)
log_info "Backing up MinIO media..."
MINIO_BACKUP_FILE="$BACKUP_DIR/minio/media_${TIMESTAMP}.tar.gz.enc"

# Create tar of MinIO data
if docker run --rm \
   -v chat-e2ee_minio_data:/data:ro \
   -v "$BACKUP_DIR/minio:/backup" \
   alpine \
   sh -c "cd /data && tar czf - chat-media chat-thumbnails" | \
   openssl enc -aes-256-cbc -salt -pass pass:"$BACKUP_ENCRYPTION_KEY" \
   > "$MINIO_BACKUP_FILE"; then
    log_info "MinIO backup completed"
else
    log_error "MinIO backup failed"
    exit 1
fi

# Backup Redis (optional - only if AOF is enabled)
if docker-compose exec -T redis keydb-cli CONFIG GET appendonly | grep -q "yes"; then
    log_info "Backing up Redis AOF..."
    if docker-compose exec -T redis keydb-cli BGSAVE && sleep 5; then
        docker cp chat_redis:/data/dump.rdb "$BACKUP_DIR/redis/dump_${TIMESTAMP}.rdb"
        openssl enc -aes-256-cbc -salt -in "$BACKUP_DIR/redis/dump_${TIMESTAMP}.rdb" \
            -out "$BACKUP_DIR/redis/dump_${TIMESTAMP}.rdb.enc" \
            -pass pass:"$BACKUP_ENCRYPTION_KEY"
        rm "$BACKUP_DIR/redis/dump_${TIMESTAMP}.rdb"
        log_info "Redis backup completed"
    else
        log_warn "Redis backup failed (non-critical)"
    fi
fi

# Create backup metadata
cat > "$BACKUP_DIR/backup_${TIMESTAMP}.json" << EOF
{
    "timestamp": "${TIMESTAMP}",
    "date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": "1.0",
    "components": {
        "postgres": "db_${TIMESTAMP}.sql.gz.enc",
        "minio": "media_${TIMESTAMP}.tar.gz.enc"
    },
    "sizes": {
        "postgres": "$(du -h "$BACKUP_DIR/postgres/db_${TIMESTAMP}.sql.gz.enc" | cut -f1)",
        "minio": "$(du -h "$MINIO_BACKUP_FILE" | cut -f1)"
    }
}
EOF

# Clean old backups
log_info "Cleaning old backups (older than ${RETENTION_DAYS} days)..."
find "$BACKUP_DIR" -type f -mtime +${RETENTION_DAYS} -delete

# Upload to B2 (if configured)
if [ -n "$B2_ACCOUNT_ID" ] && [ -n "$B2_APPLICATION_KEY" ]; then
    log_info "Uploading to Backblaze B2..."
    # This requires b2 CLI to be installed
    if command -v b2 &> /dev/null; then
        b2 authorize-account "$B2_ACCOUNT_ID" "$B2_APPLICATION_KEY"
        b2 sync "$BACKUP_DIR" "b2://${B2_BUCKET_NAME}/$(date +%Y/%m)"
        log_info "B2 upload completed"
    else
        log_warn "b2 CLI not installed, skipping cloud backup"
    fi
fi

# Summary
log_info "Backup completed successfully!"
echo -e "\n${GREEN}=== Backup Summary ===${NC}"
echo "Location: $BACKUP_DIR"
echo "Timestamp: $TIMESTAMP"
echo "PostgreSQL: $(du -h "$BACKUP_DIR/postgres/db_${TIMESTAMP}.sql.gz.enc" | cut -f1)"
echo "MinIO: $(du -h "$MINIO_BACKUP_FILE" | cut -f1)"
echo "Total size: $(du -sh "$BACKUP_DIR" | cut -f1)"

# Create restore instructions
cat > "$BACKUP_DIR/RESTORE_INSTRUCTIONS.md" << 'EOF'
# Restore Instructions

## PostgreSQL
```bash
# Decrypt and restore
openssl enc -aes-256-cbc -d -in postgres/db_TIMESTAMP.sql.gz.enc -pass pass:YOUR_KEY | \
gunzip | \
docker exec -i chat_postgres psql -U chat_user chat_e2ee
```

## MinIO
```bash
# Decrypt and restore
openssl enc -aes-256-cbc -d -in minio/media_TIMESTAMP.tar.gz.enc -pass pass:YOUR_KEY | \
docker run --rm -i -v chat-e2ee_minio_data:/data alpine tar xzf - -C /data
```
EOF

log_info "Restore instructions saved to $BACKUP_DIR/RESTORE_INSTRUCTIONS.md"