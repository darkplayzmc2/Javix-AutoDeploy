#!/bin/bash

# ==============================================================================
#  >> JAVIX REPAIR & DOCKER INSTALLER
#  >> AUTOMATICALLY FIXES MISSING COMMANDS & INSTALLS PANEL
# ==============================================================================

# 1. EMERGENCY REPAIR (Fixes 'command not found' errors)
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

if [ ! -c /dev/null ]; then
    rm -f /dev/null
    mknod -m 666 /dev/null c 1 3
fi

# Force install basic tools if they are missing
if ! command -v curl &> /dev/null; then
    echo "Repairing System Tools..."
    apt-get update -y
    apt-get install -y curl sudo git
fi

# 2. AUTO-ELEVATION
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# 3. VISUALS
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "   ██╗ █████╗ ██╗   ██╗██╗██╗  ██╗"
echo "   ██║██╔══██╗██║   ██║██║╚██╗██╔╝"
echo "   ██║███████║██║   ██║██║ ╚███╔╝ "
echo "   ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═╝"
echo -e "${GREEN}   :: DOCKER REPAIR EDITION ::${NC}"
echo ""

# 4. INSTALL DOCKER (The Engine)
echo "Installing Docker Engine..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
fi

# 5. SETUP WORKSPACE
echo "Creating Javix Workspace..."
mkdir -p /etc/javix
cd /etc/javix

# 6. CREATE DOCKER COMPOSE FILE (The Engine Room)
# This creates the Panel, Database, and Cache containers automatically.
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
      - "80:80"
    environment:
      - APP_ENV=production
      - APP_DEBUG=false
      - APP_THEME=pterodactyl
      - APP_URL=http://localhost
      - APP_TIMEZONE=UTC
      - APP_SERVICE_AUTHOR=admin@javix.com
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

# 7. START EVERYTHING
echo "Starting Containers..."
# Remove old containers if they exist
docker compose down >/dev/null 2>&1
# Start new ones
docker compose up -d

echo "Waiting for Database to wake up (10s)..."
sleep 10

# 8. CONFIGURE PANEL (Inside the container)
echo "Generating Admin User..."
docker compose exec -T panel php artisan key:generate --force
docker compose exec -T panel php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1

# 9. INSTALL WINGS (On Host)
echo "Installing Wings..."
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
chmod u+x /usr/local/bin/wings

# 10. FINAL OUTPUT
clear
echo "=========================================="
echo "      JAVIX INSTALL COMPLETE"
echo "=========================================="
echo "1. Go to CodeSandbox 'PORTS' tab -> Open Port 80."
echo "2. Login: admin@javix.com / javix123"
echo "=========================================="
echo "3. Create Node FQDN: localhost"
echo "4. Paste 'wings configure' command below:"
echo "=========================================="
echo ""
echo -n "PASTE COMMAND: "
read WINGS_CMD

echo "Configuring Wings..."
eval "$WINGS_CMD"

# Patch config to allow Docker networking
sed -i 's/0.0.0.0/0.0.0.0/g' /etc/pterodactyl/config.yml

echo "Starting Wings..."
wings --debug > wings.log 2>&1 &
echo "SUCCESS. JAVIX IS ONLINE."
