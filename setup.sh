#!/usr/bin/env bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== VPS Architecture Setup ===${NC}"

# 1. Check prerequisites
echo -e "\nChecking prerequisites..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed.${NC}"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo -e "${RED}Error: Docker Compose v2 is not installed.${NC}"
    exit 1
fi
echo -e "${GREEN}Prerequisites met (Docker and Docker Compose found).${NC}"

# 2. Initialize Shared Docker Networks
echo -e "\nInitializing shared Docker networks..."
if docker network inspect proxy-network &>/dev/null; then
    echo -e "Network 'proxy-network' already exists."
else
    docker network create proxy-network
    echo -e "${GREEN}Created 'proxy-network' network.${NC}"
fi

if docker network inspect socket-network &>/dev/null; then
    echo -e "Network 'socket-network' already exists."
else
    docker network create socket-network
    echo -e "${GREEN}Created 'socket-network' network.${NC}"
fi

# 3. Check Swap space
echo -e "\nChecking Swap space..."
if [ -f /proc/swaps ]; then
    SWAP_TOTAL=$(free -m | awk '/^Swap:/{print $2}')
    if [ "$SWAP_TOTAL" -eq 0 ]; then
        echo -e "${RED}Warning: No Swap space detected!${NC}"
        echo -e "Running a 2GB VPS without swap risks database and web app OOM crashes."
        echo -e "Recommended action: Enable at least 2GB of swap space."
    else
        echo -e "${GREEN}Swap space detected: ${SWAP_TOTAL}MB.${NC}"
    fi
else
    echo -e "${RED}Warning: Swap memory check skipped (non-standard Linux proc fs).${NC}"
fi

# 4. Setup Env Files
echo -e "\nInitializing environment files..."
KOMODO_ENV="komodo/.env"
KOMODO_EXAMPLE="komodo/.env.example"

if [ -f "$KOMODO_ENV" ]; then
    echo -e "'$KOMODO_ENV' already exists."
else
    if [ -f "$KOMODO_EXAMPLE" ]; then
        cp "$KOMODO_EXAMPLE" "$KOMODO_ENV"
        echo -e "${GREEN}Created '$KOMODO_ENV' from example template.${NC}"
        echo -e "${RED}ACTION REQUIRED: Edit '$KOMODO_ENV' to set secure passwords!${NC}"
    else
        echo -e "${RED}Error: '$KOMODO_EXAMPLE' not found.${NC}"
        exit 1
    fi
fi

echo -e "\n${GREEN}Setup completed successfully!${NC}"
echo -e "To start your stack, run:"
echo -e "  docker compose -f socket-proxy/docker-compose.yml up -d"
echo -e "  docker compose -f npm/docker-compose.yml up -d"
echo -e "  docker compose -f dozzle/docker-compose.yml up -d"
echo -e "  docker compose -f uptime/docker-compose.yml up -d"
echo -e "  docker compose -f komodo/docker-compose.yml up -d"
