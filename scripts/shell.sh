#!/bin/bash

# Access shells for Chat E2EE services

cd "$(dirname "$0")/../docker"

# Load environment
if [ -f ".env" ]; then
    set -a
    source .env
    set +a
fi

case "$1" in
    postgres|psql|db)
        echo "Connecting to PostgreSQL..."
        docker-compose exec postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" "${@:2}"
        ;;
    redis)
        echo "Connecting to Redis..."
        docker-compose exec redis keydb-cli -a "$REDIS_PASSWORD" "${@:2}"
        ;;
    backend)
        echo "Connecting to backend container..."
        docker-compose exec backend /bin/sh
        ;;
    minio)
        echo "Connecting to MinIO container..."
        docker-compose exec minio /bin/sh
        ;;
    *)
        echo "Usage: $0 [postgres|redis|backend|minio]"
        echo "Examples:"
        echo "  $0 postgres          # PostgreSQL shell"
        echo "  $0 postgres 'SELECT * FROM users'"
        echo "  $0 redis             # Redis CLI"
        echo "  $0 redis INFO"
        echo "  $0 backend           # Backend container shell"
        exit 1
        ;;
esac
