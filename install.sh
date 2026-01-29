#!/bin/bash

# ==============================================================================
#  >> JAVIX-AUTODEPLOY | HYPER-AUTO EDITION (ZERO TOUCH)
#  >> AUTHOR: sk mohsin pasha
#  >> FEATURES: Auto-Wipe, Auto-DDoS (Tunnel), Silent Install
# ==============================================================================

# --- 0. AUTO-ELEVATION ---
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# --- 1. VISUALS ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

logo() {
    clear
    echo -e "${CYAN}"
    echo "   ██╗ █████╗ ██╗   ██╗██╗██╗  ██╗"
    echo "   ██║██╔══██╗██║   ██║██║╚██╗██╔╝"
    echo "   ██║███████║██║   ██║██║ ╚███╔╝ "
    echo "   ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${RED}   :: DESTRUCTIVE MODE :: HYPER-AUTO ::${NC}"
    echo ""
}

# --- 2. THE CLEANUP (DELETES PREVIOUS SCRIPT) ---
logo
echo -e "${RED}[JAVIX] PERFORMING FACTORY RESET (Wiping old data)...${NC}"
# Stop services
systemctl stop wings pteroq >/dev/null 2>&1
docker stop $(docker ps -a -q) >/dev/null 2>&1
docker rm $(docker ps -a -q) >/dev/null 2>&1

# Delete files
rm -rf /var/www/pterodactyl
rm -rf /etc/pterodactyl
rm -rf /var/lib/mysql
rm -f /usr/local/bin/wings
rm -f /usr/local/bin/composer

echo -e "${GREEN}[JAVIX] Cleanup Complete. Fresh install starting.${NC}"
sleep 2

# --- 3. AUTO-INSTALL DEPENDENCIES & DDOS PROTECTION ---
echo -e "${YELLOW}[JAVIX] Installing Dependencies & Anti-DDoS Tunnel...${NC}"

# Silent Install of Deps
apt-get update -q >/dev/null 2>&1
apt-get install -y curl tar unzip git jq certbot >/dev/null 2>&1

# Install Docker if missing
if ! command -v docker &> /dev/null; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash >/dev/null 2>&1
fi
systemctl enable --now docker >/dev/null 2>&1

# Install Cloudflare Tunnel (The Best Free DDoS Protection)
# This hides your server IP completely behind Cloudflare.
curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >/dev/null 2>&1
dpkg -i cloudflared.deb >/dev/null 2>&1

# --- 4. SILENT PANEL INSTALLATION ---
echo -e "${YELLOW}[JAVIX] Installing Pterodactyl Panel (Silent Mode)...${NC}"

mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl

# Download Panel
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz >/dev/null 2>&1
tar -xzvf panel.tar.gz >/dev/null 2>&1
chmod -R 755 storage bootstrap/cache

# Install Database (MariaDB) - Silent
apt-get install -y mariadb-server mariadb-client >/dev/null 2>&1
systemctl enable --now mariadb >/dev/null 2>&1

# Create Database & User Automagically
mysql -u root -e "CREATE USER 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'javix123';"
mysql -u root -e "CREATE DATABASE panel;"
mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"

# Setup PHP/Composer
apt-get install -y php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} >/dev/null 2>&1
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1

# Run Panel Setup (Auto-filling answers)
cp .env.example .env
composer install --no-dev --optimize-autoloader --no-interaction >/dev/null 2>&1
php artisan key:generate --force >/dev/null 2>&1

# Configure Environment Variables manually to skip interactive setup
sed -i 's/DB_PASSWORD=/DB_PASSWORD=javix123/g' .env
sed -i 's/APP_URL=http:\/\/localhost/APP_URL=http:\/\/localhost:80/g' .env

php artisan migrate --seed --force >/dev/null 2>&1

# Create Default Admin User (admin / javix123)
php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1 >/dev/null 2>&1

echo -e "${GREEN}[JAVIX] Panel Installed. User: admin@javix.com | Pass: javix123${NC}"

# --- 5. SILENT WINGS INSTALLATION ---
echo -e "${YELLOW}[JAVIX] Installing Wings (Silent Mode)...${NC}"
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
chmod u+x /usr/local/bin/wings

# --- 6. THE "MAGIC" CONNECTION (TUNNEL + OUTPUT) ---
logo

# Start Cloudflare Tunnel in Background
# This gives you a Public URL immediately
cloudflared tunnel --url http://localhost:80 > tunnel.log 2>&1 &
echo -e "${YELLOW}[JAVIX] Generating Secure Public URL...${NC}"
sleep 8
TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)

# Configure Panel URL to use the Tunnel
cd /var/www/pterodactyl
sed -i "s|APP_URL=http://localhost:80|APP_URL=${TUNNEL_URL}|g" .env
php artisan config:clear >/dev/null 2>&1

# Start Queue Worker
php artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 >/dev/null 2>&1 &

# --- 7. FINAL READY-TO-USE OUTPUT ---
clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${GREEN}      JAVIX INSTALLATION COMPLETE (NO INPUTS USED) ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo ""
echo -e "YOUR PANEL IS ONLINE HERE: ${YELLOW}${TUNNEL_URL}${NC}"
echo -e "LOGIN EMAIL:  ${GREEN}admin@javix.com${NC}"
echo -e "LOGIN PASS:   ${GREEN}javix123${NC}"
echo ""
echo -e "${RED}ACTION REQUIRED (The only step left):${NC}"
echo "1. Login to the Panel."
echo "2. Go to Admin -> Nodes -> Create New."
echo "3. Use FQDN: ${TUNNEL_URL} (Remove https://)"
echo "4. Click 'Configuration' tab, copy the command, and paste it here to start Wings."
echo ""
echo -e "${CYAN}====================================================${NC}"

# Start Wings in Debug mode (Waiting for config)
echo "Ready for Wings command..."
bash
