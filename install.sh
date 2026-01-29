#!/bin/bash

# ==============================================================================
#  >> JAVIX PORT FORCER EDITION
#  >> FEATURES: Manual Port Trigger, invalid URL fix, Port 3000
# ==============================================================================

# 1. CLEANUP (Kill everything)
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi
echo "Clearing ports..."
fuser -k 3000/tcp >/dev/null 2>&1
fuser -k 80/tcp >/dev/null 2>&1

# 2. INSTALL BASICS
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
    echo -e "${GREEN}    :: PORT FORCER EDITION ::${NC}"
    echo ""
}

# --- 4. THE MENU ---
logo
echo -e "${YELLOW}--- ENVIRONMENT SELECTION ---${NC}"
echo "1) Paid VPS (DigitalOcean, AWS)"
echo "2) CodeSandbox (Free - Force Port 3000)"
echo ""
echo -n "Select environment [1-2]: "
read ENV_TYPE

echo ""
echo -e "${YELLOW}--- COMPONENT SELECTION ---${NC}"
echo "1) Full Stack (Panel + Wings)"
echo "2) Wings Only"
echo ""
echo -n "Select install mode [1-2]: "
read INSTALL_MODE

# --- 5. INSTALL DOCKER ---
logo
echo -e "${CYAN}[JAVIX]${NC} Setting up Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh >/dev/null 2>&1
fi

# --- 6. CONFIGURATION ---
mkdir -p /etc/javix
cd /etc/javix
APP_PORT="3000"

# Set a temporary URL to allow boot
APP_URL="http://localhost:3000"

cat > docker-compose.yml <<EOF
version: '3.8'
services:
  database:
    image: mariadb:10.5
    restart: always
    command: --default-authentication-plugin=mysql_native_password
    volumes:
      - "/var/lib/javix/database:/var/lib/mysql"
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
    ports:
      - "${APP_PORT}:80"
    environment:
      - APP_ENV=production
      - APP_DEBUG=true
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
      - "/var/www/javix/var/:/app/var/"
      - "/var/www/javix/storage/logs:/app/storage/logs"
      - "/var/www/javix/storage/app/public:/app/storage/app/public"
EOF

# --- 7. START AND FORCE PORT ---
echo -e "${CYAN}[JAVIX]${NC} Starting Panel on Port 3000..."
docker compose down >/dev/null 2>&1
docker compose up -d

# --- 8. THE MANUAL PORT TRIGGER ---
if [ "$ENV_TYPE" == "2" ]; then
    logo
    echo -e "${YELLOW}====================================================${NC}"
    echo -e "${RED}      IF YOU SEE 'NO PORTS' - DO THIS NOW:      ${NC}"
    echo -e "${YELLOW}====================================================${NC}"
    echo "1. Look at the 'PORTS' tab."
    echo "2. If it is empty, click the green 'Add Port' button."
    echo "3. Type: 3000"
    echo "4. Press Enter."
    echo ""
    echo "Once you see Port 3000 in the list, copy the address."
    echo "(It looks like: https://something-3000.csb.app/)"
    echo ""
    echo -n "PASTE THE URL HERE: "
    read CSB_URL
    
    # Clean URL
    CSB_URL=${CSB_URL%/}

    echo -e "${CYAN}[JAVIX]${NC} Fixing Invalid URL Error..."
    sed -i "s|APP_URL=http://localhost:3000|APP_URL=${CSB_URL}|g" docker-compose.yml
    
    # Apply Fix
    docker compose up -d
    
    # Create Admin User NOW (After URL fix)
    echo "Creating Admin User..."
    sleep 5
    docker compose exec -T panel php artisan key:generate --force >/dev/null 2>&1
    docker compose exec -T panel php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1 >/dev/null 2>&1
fi

# --- 9. WINGS ---
if [ "$INSTALL_MODE" == "1" ]; then
    echo "Installing Wings..."
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings
fi

# --- 10. FINAL OUTPUT ---
logo
echo "=========================================="
echo "      JAVIX INSTALLATION COMPLETE"
echo "=========================================="
if [ "$ENV_TYPE" == "2" ]; then
    echo -e "PANEL URL: ${GREEN}${CSB_URL}${NC}"
    echo -e "Node FQDN: ${GREEN}localhost${NC}"
else
    echo "MODE: Paid VPS"
fi
echo "=========================================="
echo "Login: admin@javix.com / javix123"
echo "=========================================="

if [ "$INSTALL_MODE" == "1" ]; then
    echo -e "${YELLOW}PASTE 'wings configure' COMMAND:${NC}"
    read WINGS_CMD
    eval "$WINGS_CMD"
    sed -i 's/0.0.0.0/0.0.0.0/g' /etc/pterodactyl/config.yml
    wings --debug > wings.log 2>&1 &
    echo -e "${GREEN}SUCCESS! JAVIX IS ONLINE.${NC}"
fi
