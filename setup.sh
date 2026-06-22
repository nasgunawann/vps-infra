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
        read -p "Would you like to automatically create and enable a 2GB swap file? (y/N): " CREATE_SWAP
        CREATE_SWAP=${CREATE_SWAP:-N}
        if [[ "$CREATE_SWAP" =~ ^[Yy]$ ]]; then
            echo "Creating 2GB swap file..."
            if fallocate -l 2G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=2048; then
                chmod 600 /swapfile
                mkswap /swapfile
                swapon /swapfile
                if ! grep -q "/swapfile" /etc/fstab; then
                    echo '/swapfile none swap sw 0 0' >> /etc/fstab
                fi
                echo -e "${GREEN}2GB Swap file successfully created and enabled!${NC}"
            else
                echo -e "${RED}Failed to create swap file. Please configure swap manually.${NC}"
            fi
        fi
    else
        echo -e "${GREEN}Swap space detected: ${SWAP_TOTAL}MB.${NC}"
    fi
else
    echo -e "${RED}Warning: Swap memory check skipped (non-standard Linux proc fs).${NC}"
fi

# 4. Setup Env Files
echo -e "\nInitializing environment files..."
KOMODO_ENV="komodo/.env"

if [ -f "$KOMODO_ENV" ]; then
    echo -e "'$KOMODO_ENV' already exists."
else
    # Helper to generate secure random keys
    if command -v openssl &> /dev/null; then
        GEN_SECRET() { openssl rand -hex 16; }
        GEN_JWT() { openssl rand -hex 32; }
    elif command -v python3 &> /dev/null; then
        GEN_SECRET() { python3 -c "import secrets; print(secrets.token_hex(16))"; }
        GEN_JWT() { python3 -c "import secrets; print(secrets.token_hex(32))"; }
    else
        GEN_SECRET() { tr -dc 'a-f0-9' </dev/urandom | head -c 32; }
        GEN_JWT() { tr -dc 'a-f0-9' </dev/urandom | head -c 64; }
    fi

    # Prompt for admin username
    read -p "Enter custom admin username (default: vps_admin): " ADMIN_USER
    ADMIN_USER=${ADMIN_USER:-vps_admin}

    # Generate credentials
    DB_USER="komodo_db_admin"
    DB_PASS=$(GEN_SECRET)
    ADMIN_PASS=$(GEN_SECRET)
    JWT_SECRET=$(GEN_JWT)
    WEBHOOK_SECRET=$(GEN_JWT)

    # Write .env file
    cat <<EOF > "$KOMODO_ENV"
# Database Credentials
KOMODO_DB_USER=$DB_USER
KOMODO_DB_PASSWORD=$DB_PASS

# Initial Setup
KOMODO_ADMIN_USER=$ADMIN_USER
KOMODO_ADMIN_PASSWORD=$ADMIN_PASS

# Secrets
KOMODO_JWT_SECRET=$JWT_SECRET
KOMODO_WEBHOOK_SECRET=$WEBHOOK_SECRET
EOF

    echo -e "${GREEN}Successfully generated '$KOMODO_ENV'!${NC}"
    echo -e "\n--------------------------------------------------"
    echo -e "  ${BLUE}YOUR DEPLOYED ADMINISTRATIVE CREDENTIALS${NC}"
    echo -e "--------------------------------------------------"
    echo -e "  Admin Username: ${GREEN}$ADMIN_USER${NC}"
    echo -e "  Admin Password: ${GREEN}$ADMIN_PASS${NC}"
    echo -e "--------------------------------------------------"
    echo -e "  (Keep these details secure! They have been saved to $KOMODO_ENV)${NC}\n"
fi

# 5. Start infrastructure confirmation
echo -e "\nWould you like to start the docker containers now? (Y/n)"
read -r START_INFRA
START_INFRA=${START_INFRA:-Y}

if [[ "$START_INFRA" =~ ^[Yy]$ ]]; then
    echo -e "\nStarting infrastructure..."
    docker compose -f socket-proxy/docker-compose.yml up -d
    docker compose -f npm/docker-compose.yml up -d
    docker compose -f uptime/docker-compose.yml up -d
    docker compose -f komodo/docker-compose.yml up -d
    echo -e "\n${GREEN}Infrastructure successfully started!${NC}"
else
    echo -e "\nSetup completed. You can start the infrastructure manually using:"
    echo -e "  docker compose -f socket-proxy/docker-compose.yml up -d"
    echo -e "  docker compose -f npm/docker-compose.yml up -d"
    echo -e "  docker compose -f uptime/docker-compose.yml up -d"
    echo -e "  docker compose -f komodo/docker-compose.yml up -d"
fi
