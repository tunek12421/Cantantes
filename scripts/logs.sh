#!/bin/bash

# Logs viewer for Chat E2EE services

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Navigate to docker directory
cd "$SCRIPT_DIR/../docker"

# Service name from argument
SERVICE=$1

# Show help if no argument
if [ -z "$SERVICE" ]; then
    echo "Usage: $0 [service|all]"
    echo "Services: postgres, redis, minio, pgadmin, all"
    echo "Options:"
    echo "  -f    Follow log output"
    echo "Example: $0 postgres -f"
    exit 1
fi

# Check if follow flag is set
FOLLOW=""
if [ "$2" == "-f" ]; then
    FOLLOW="-f"
fi

# Show logs
case $SERVICE in
    all)
        docker-compose logs $FOLLOW
        ;;
    postgres|redis|minio|pgadmin)
        docker-compose logs $FOLLOW $SERVICE
        ;;
    *)
        echo "Unknown service: $SERVICE"
        echo "Available services: postgres, redis, minio, pgadmin, all"
        exit 1
        ;;
esac

# Show help if no argument
if [ -z "$SERVICE" ]; then
    echo "Usage: $0 [service|all]"
    echo "Services: postgres, redis, minio, pgadmin, backend, all"
    echo "Options:"
    echo "  -f    Follow log output"
    echo "Example: $0 postgres -f"
    exit 1
fi