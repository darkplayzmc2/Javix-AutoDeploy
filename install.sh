#!/bin/bash

# ==============================================================================
#  >> JAVIX LAZARUS PROTOCOL (THE FINAL FIX)
#  >> REBUILDS LINUX PATHS, RESTORES /DEV/NULL, FORCES PORT 80
# ==============================================================================

# 1. FORCE RESTORE SYSTEM PATHS (Fixes 'command not found')
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 2. FIX /DEV/NULL (Fixes 'No such file or directory')
if [ ! -c /dev/null ]; then
    echo "System is corrupted. Recreating /dev/null..."
    rm -f /dev/null
    mknod -m 666 /dev/null c 1 3
fi

# 3. FORCE INSTALL BASIC TOOLS
echo "Restoring Linux System Tools..."
apt-get update --fix-missing -y
apt-get install -y --reinstall coreutils curl wget git unzip sed

# 4. START INSTALLATION (Stop on any error)
set -e 

# --- VISUALS ---
CYAN='\033[0;36m'
GREEN='\033[0;32m'
NC='\033[0m'

clear
echo -e "${CYAN}"
echo "   ██╗ █████╗ ██╗   ██╗██╗██╗  ██╗"
echo "   ██║██╔══██╗██║   ██║██║╚██╗██╔╝"
echo "   ██║███████║██║   ██║██║ ╚███╔╝ "
echo "   ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═╝"
echo -e "${GREEN}   :: SYSTEM RESTORED & INSTALLING ::${NC}"
echo ""

# --- CLEANUP ---
echo "Wiping old broken files..."
rm -rf /var/www/pterodactyl /etc/pterodactyl /usr/local/bin/wings
# Ignore docker errors if docker is dead
docker rm -f $(docker ps -a -q) || true

# --- INSTALL DOCKER & DATABASE ---
echo "Installing Dependencies..."
if ! command -v docker &> /dev/null; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
fi
service docker start
service mariadb start

# --- DATABASE SETUP ---
echo "Configuring Database..."
mysql -u root -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'javix123';"
mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel;"
mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"

# --- PANEL FILES ---
echo "Downloading Panel..."
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage bootstrap/cache

# --- PHP & COMPOSER ---
echo "Installing PHP..."
apt-get install -y php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip}
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

echo "Installing Composer Dependencies..."
cp .env.example .env
composer install --no-dev --optimize-autoloader --no-interaction
php artisan key:generate --force

# --- CODESANDBOX CONFIGURATION ---
echo "Applying CodeSandbox Patches..."
sed -i 's/DB_PASSWORD=/DB_PASSWORD=javix123/g' .env
sed -i "s|APP_URL=http://localhost|APP_URL=http://localhost|g" .env
sed -i "s|APP_URL=https://panel.example.com|APP_URL=http://localhost|g" .env

php artisan migrate --seed --force
php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1

# --- WINGS INSTALLATION ---
echo "Installing Wings..."
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
chmod u+x /usr/local/bin/wings

# --- FORCE PORT 80 ---
echo "Starting Server on Port 80..."
# Kill anything on port 80
fuser -k 80/tcp || true
# Start PHP server in background
nohup php artisan serve --host=0.0.0.0 --port=80 > panel.log 2>&1 &

# --- FINAL OUTPUT ---
clear
echo "=========================================="
echo "      JAVIX INSTALLATION SUCCESSFUL"
echo "=========================================="
echo "PANEL IS ONLINE"
echo "Login: admin@javix.com / javix123"
echo "=========================================="
echo "1. Go to 'PORTS' tab -> Click Open on Port 80."
echo "2. Create Node FQDN: localhost"
echo "3. Copy the 'wings configure' command."
echo "4. Paste it below to finish."
echo "=========================================="
echo ""
echo -n "PASTE WINGS COMMAND HERE: "
read WINGS_CMD

echo "Starting Wings..."
eval "$WINGS_CMD"
wings --debug > wings.log 2>&1 &
echo "SUCCESS. Wings is running."
