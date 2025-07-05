#!/bin/bash

# System information for Chat E2EE deployment

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}=== System Information ===${NC}\n"

# OS Information
echo -e "${YELLOW}Operating System:${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "OS: $NAME $VERSION"
fi
uname -a

# Hardware
echo -e "\n${YELLOW}Hardware:${NC}"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
echo "Cores: $(nproc)"
echo "RAM: $(free -h | grep Mem | awk '{print $2}')"
echo "Available RAM: $(free -h | grep Mem | awk '{print $7}')"

# Disk Space
echo -e "\n${YELLOW}Disk Space:${NC}"
df -h / | grep -v Filesystem

# Docker Information
echo -e "\n${YELLOW}Docker:${NC}"
docker --version
docker-compose --version
echo "Docker daemon: $(systemctl is-active docker)"

# Network
echo -e "\n${YELLOW}Network:${NC}"
echo "Hostname: $(hostname)"
echo "IP: $(hostname -I | cut -d' ' -f1)"

# Project Space
echo -e "\n${YELLOW}Project Disk Usage:${NC}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
du -sh "$PROJECT_DIR" 2>/dev/null
du -sh "$PROJECT_DIR"/{data,logs,docker} 2>/dev/null

# Docker Resources
echo -e "\n${YELLOW}Docker Resources:${NC}"
docker system df

# Running Containers
echo -e "\n${YELLOW}Chat E2EE Containers:${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(NAMES|chat_)"

echo -e "\n${GREEN}System check complete!${NC}"