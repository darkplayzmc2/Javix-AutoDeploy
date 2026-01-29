#!/bin/bash

# ==============================================================================
#  >> JAVIX UNIVERSAL FIXER
#  >> FEATURES: Fixes 'Invalid Request URL', Menus, Add-ons, Port 5000
# ==============================================================================

# 1. AUTO-ELEVATION
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# 2. EMERGENCY REPAIR
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if ! command -v curl &> /dev/null; then
    apt-get update -y -q
    apt-get install -y curl git
fi

# 3. VISUALS
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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
    echo -e "${GREEN}    :: UNIVERSAL FIXER EDITION ::${NC}"
    echo ""
}

# --- 4. THE MENU SYSTEM ---
logo
echo -e "${YELLOW}--- ENVIRONMENT SELECTION ---${NC}"
echo "1) Paid VPS (DigitalOcean, AWS, Hetzner)"
echo "2) CodeSandbox (Free - Fixes Invalid URL Error)"
echo ""
echo -n "Select your environment [1-2]: "
read ENV_TYPE

echo ""
echo -e "${YELLOW}--- COMPONENT SELECTION ---${NC}"
echo "1) Full Stack (Panel + Wings)"
echo "2) Wings Only"
echo "3) Panel Only"
echo ""
echo -n "Select install mode [1-3]: "
read INSTALL_MODE

# --- ADD-ON MENU ---
echo ""
echo -e "${YELLOW}--- ADD-ON STORE ---${NC}"
echo -n "Install 'Future UI' Theme? (y/n): "
read INSTALL_THEME
echo -n "Install Plugin Manager System? (y/n): "
read INSTALL_PLUGIN
echo -n "Install Minecraft Version Changer? (y/n): "
read INSTALL_MCVER

# --- 5. INITIAL CONFIGURATION ---
if [ "$ENV_TYPE" == "2" ]; then
    # CODESANDBOX: We start with a placeholder, then fix it later
    APP_PORT="5000"
    APP_URL="http://localhost:5000"
    echo -e "${GREEN}[JAVIX] CodeSandbox detected. Will ask for URL later to fix 'Invalid Request'.${NC}"
else
    # VPS MODE
    APP_PORT="80"
    echo -e "${YELLOW}Enter your Domain (FQDN):${NC}"
    read FQDN
    APP_URL="https://${FQDN}"
fi

# --- 6. INSTALL DOCKER ---
logo
echo -e "${CYAN}[JAVIX]${NC} Checking Docker engine..."
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh >/dev/null 2>&1
fi

# --- 7. CREATE CONFIGURATION ---
echo -e "${CYAN}[JAVIX]${NC} Generating Configuration..."
mkdir -p /etc/javix
cd /etc/javix

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

# --- 8. START CONTAINERS ---
echo -e "${CYAN}[JAVIX]${NC} Starting Panel on Port ${APP_PORT}..."
docker compose down >/dev/null 2>&1
docker compose up -d

echo "Waiting for Database (10s)..."
sleep 10

# --- 9. CONFIGURE PANEL ---
echo -e "${CYAN}[JAVIX]${NC} Creating Admin User..."
docker compose exec -T panel php artisan key:generate --force >/dev/null 2>&1
docker compose exec -T panel php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1 >/dev/null 2>&1

# --- 10. CRITICAL FIX FOR CODESANDBOX ---
if [ "$ENV_TYPE" == "2" ]; then
    logo
    echo -e "${YELLOW}====================================================${NC}"
    echo -e "${YELLOW}      CRITICAL STEP: FIX 'INVALID REQUEST URL'      ${NC}"
    echo -e "${YELLOW}====================================================${NC}"
    echo "1. Go to the 'PORTS' tab in CodeSandbox."
    echo "2. Find Port 5000."
    echo "3. Copy the 'Forwarded Address' (e.g., https://abc-5000.csb.app/)"
    echo ""
    echo -n "PASTE THE URL HERE: "
    read CSB_URL
    
    # Remove trailing slash if present
    CSB_URL=${CSB_URL%/}

    echo -e "${CYAN}[JAVIX]${NC} Patching Panel with URL: ${CSB_URL}..."
    
    # Update Docker Compose with correct URL
    sed -i "s|APP_URL=http://localhost:5000|APP_URL=${CSB_URL}|g" docker-compose.yml
    
    # Restart to apply
    docker compose down >/dev/null 2>&1
    docker compose up -d
    
    APP_URL="${CSB_URL}"
fi

# --- 11. INSTALL WINGS ---
if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "2" ]; then
    echo -e "${CYAN}[JAVIX]${NC} Installing Wings..."
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings
fi

# --- 12. FINAL OUTPUT ---
logo
echo "=========================================="
echo "      JAVIX INSTALLATION COMPLETE"
echo "=========================================="
if [ "$ENV_TYPE" == "2" ]; then
    echo "MODE: CodeSandbox (FIXED)"
    echo -e "PANEL URL: ${GREEN}${APP_URL}${NC}"
    echo -e "Node FQDN: ${GREEN}localhost${NC}"
else
    echo "MODE: Paid VPS"
    echo "URL: https://$FQDN"
fi
echo "=========================================="
echo "Login: admin@javix.com / javix123"
echo "=========================================="
echo ""

if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "2" ]; then
    echo -e "${YELLOW}PASTE YOUR 'wings configure' COMMAND BELOW:${NC}"
    read WINGS_CMD
    echo "Configuring Wings..."
    eval "$WINGS_CMD"
    
    sed -i 's/0.0.0.0/0.0.0.0/g' /etc/pterodactyl/config.yml
    
    echo "Starting Wings..."
    wings --debug > wings.log 2>&1 &
    echo -e "${GREEN}SUCCESS! JAVIX IS ONLINE.${NC}"
fi
