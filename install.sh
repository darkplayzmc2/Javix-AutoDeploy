#!/bin/bash

# ==============================================================================
#  >> JAVIX SEQUENTIAL EDITION (NO CRASH)
#  >> FEATURES: Installs Database FIRST, then Panel, then Wings. Saves RAM.
# ==============================================================================

# 1. CHECK ROOT
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# 2. CLEANUP & PREP
RUN_ID="run_$(date +%s)"
echo "Starting Install (Session: $RUN_ID)..."

echo "Stopping old containers..."
docker compose down -v >/dev/null 2>&1
fuser -k 3000/tcp >/dev/null 2>&1

# Fix tools
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if ! command -v curl &> /dev/null; then
    apt-get update -y -q
    apt-get install -y curl git
fi

# 3. VISUALS
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

logo() {
    clear
    echo -e "${CYAN}"
    echo "       ██╗ █████╗ ██╗   ██╗██╗██╗  ██╗"
    echo "       ██║██╔══██╗██║   ██║██║╚██╗██╔╝"
    echo "       ██║███████║██║   ██║██║ ╚███╔╝ "
    echo "  ██   ██║██╔══██║╚██╗ ██╔╝██║ ██╔██╗ "
    echo "  ╚█████╔╝██║  ██║ ╚████╔╝ ██║██╔╝ ██╗"
    echo "   ╚════╝ ╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${GREEN}    :: SEQUENTIAL INSTALLER ::${NC}"
    echo ""
}

# --- 4. CONFIGURATION ---
logo
echo -e "${CYAN}[JAVIX]${NC} Setting up Workspace..."
mkdir -p /etc/javix
cd /etc/javix

APP_URL="http://localhost:3000"

# --- DOCKER COMPOSE (LOW RAM) ---
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  database:
    image: mariadb:10.5
    restart: always
    command: --default-authentication-plugin=mysql_native_password --innodb-buffer-pool-size=10M --innodb-log-buffer-size=256K --max-connections=20
    volumes:
      - javix_db_$RUN_ID:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=javix_root
      - MYSQL_DATABASE=panel
      - MYSQL_USER=pterodactyl
      - MYSQL_PASSWORD=javix123
    ports:
      - "3306:3306"
  cache:
    image: redis:alpine
    restart: always
  panel:
    image: ghcr.io/pterodactyl/panel:latest
    restart: always
    user: root
    ports:
      - "3000:80"
    environment:
      - APP_ENV=production
      - APP_DEBUG=false
      - APP_THEME=pterodactyl
      - APP_URL=${APP_URL}
      - APP_TIMEZONE=UTC
      - APP_SERVICE_AUTHOR=admin@javix.com
      - TRUSTED_PROXIES=*
      - DB_HOST=database
      - DB_PORT=3306
      - DB_DATABASE=panel
      - DB_USERNAME=pterodactyl
      - DB_PASSWORD=javix123
      - CACHE_DRIVER=redis
      - SESSION_DRIVER=redis
      - QUEUE_CONNECTION=redis
      - REDIS_HOST=cache
    depends_on:
      - database
      - cache
    volumes:
      - javix_var_$RUN_ID:/app/var/
      - javix_logs_$RUN_ID:/app/storage/logs
      - javix_public_$RUN_ID:/app/storage/app/public

volumes:
  javix_db_$RUN_ID:
  javix_var_$RUN_ID:
  javix_logs_$RUN_ID:
  javix_public_$RUN_ID:
EOF

# --- 5. PHASE 1: DATABASE START ---
logo
echo -e "${YELLOW}Phase 1: Starting Database Only...${NC}"
docker compose up -d database cache

echo "Waiting for Database to wake up (15s)..."
sleep 15

# --- 6. PHASE 2: PANEL SETUP (INTERACTIVE) ---
logo
echo -e "${YELLOW}Phase 2: Running Pterodactyl Setup Commands...${NC}"
echo -e "${CYAN}Running Migrations (Creating Tables)...${NC}"

# Start panel temporarily to run commands
docker compose run --rm panel php artisan migrate --seed --force

echo ""
echo -e "${CYAN}Creating Admin User...${NC}"
docker compose run --rm panel php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1

# --- 7. PHASE 3: PANEL BOOT ---
logo
echo -e "${YELLOW}Phase 3: Starting Web Panel...${NC}"
docker compose up -d panel

# --- 8. PHASE 4: URL FIX ---
logo
echo -e "${YELLOW}====================================================${NC}"
echo -e "${RED}      CRITICAL: FIX THE URL TO CONTINUE      ${NC}"
echo -e "${YELLOW}====================================================${NC}"
echo "1. Go to 'PORTS' tab."
echo "2. Ensure Port 3000 is Open."
echo "3. Copy the address (e.g., https://abc-3000.csb.app/)"
echo ""
echo -n "PASTE URL HERE: "
read CSB_URL
CSB_URL=${CSB_URL%/}

echo -e "${CYAN}[JAVIX]${NC} Applying URL..."
sed -i "s|APP_URL=http://localhost:3000|APP_URL=${CSB_URL}|g" docker-compose.yml
docker compose up -d
APP_URL="${CSB_URL}"

echo "Waiting for Panel to reload (10s)..."
sleep 10

# --- 9. PHASE 5: WINGS SETUP ---
logo
echo "=========================================="
echo "      PANEL INSTALLED SUCCESSFULLY"
echo "=========================================="
echo -e "URL: ${GREEN}${APP_URL}${NC}"
echo -e "Login: ${CYAN}admin@javix.com${NC} / ${CYAN}javix123${NC}"
echo "=========================================="
echo ""
echo -e "${YELLOW}--- NEXT STEPS FOR WINGS ---${NC}"
echo "1. Open the Panel URL above."
echo "2. Log in."
echo "3. Go to Admin -> Locations -> Create 'Home'."
echo "4. Go to Admin -> Nodes -> Create New."
echo "   - Name: Node1"
echo "   - FQDN: localhost"
echo "   - RAM/Disk: 2048 / 10000"
echo "   - Daemon Port: 8081"
echo "5. Click 'Configuration' tab in the Node settings."
echo "6. Copy the command block that starts with 'cd /etc/pterodactyl && sudo wings...'"
echo ""
echo -e "${RED}PASTE THE COMMAND BELOW TO INSTALL WINGS:${NC}"
read WINGS_CMD

echo ""
echo -e "${CYAN}[JAVIX]${NC} Installing Wings..."
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
chmod u+x /usr/local/bin/wings

echo -e "${CYAN}[JAVIX]${NC} Configuring Wings..."
eval "$WINGS_CMD"

# Fix Wings Config for Docker
sed -i 's/0.0.0.0/0.0.0.0/g' /etc/pterodactyl/config.yml
sed -i 's/cd \/etc\/pterodactyl && sudo wings configure --panel-url//g' /etc/pterodactyl/config.yml 2>/dev/null

echo -e "${GREEN}[JAVIX]${NC} Starting Wings..."
wings --debug > wings.log 2>&1 &

echo ""
echo "=========================================="
echo "      FULL INSTALLATION COMPLETE"
echo "=========================================="
echo "Panel & Wings are running."
echo "You can now create servers."
