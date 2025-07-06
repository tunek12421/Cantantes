#!/bin/bash

# View logs for Chat E2EE services

cd "$(dirname "$0")/../docker"

SERVICE=$1
FOLLOW=""

if [ "$2" == "-f" ] || [ "$1" == "-f" ]; then
    FOLLOW="-f"
fi

if [ -z "$SERVICE" ] || [ "$SERVICE" == "-f" ]; then
    docker-compose logs $FOLLOW
else
    docker-compose logs $FOLLOW $SERVICE
fi
