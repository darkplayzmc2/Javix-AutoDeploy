#!/bin/bash

# ==============================================================================
#  >> JAVIX-AUTODEPLOY | FINAL STABLE EDITION
#  >> FEATURES: Menu System, Port 80 Force, Auto-Dependency Installer
# ==============================================================================

# --- 0. CHECK & ELEVATE ---
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# --- 1. PRE-FLIGHT CHECK (ENSURES TOOLS EXIST) ---
echo "Checking Environment..."
if ! command -v curl &> /dev/null; then
    echo "Installing missing core tools..."
    apt-get update -y
    apt-get install -y curl tar unzip git jq certbot
fi

# --- 2. VISUALS ---
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
    echo -e "${GREEN}    :: FINAL STABLE EDITION ::${NC}"
    echo ""
}

# --- 3. THE MENU SYSTEM ---
logo
echo -e "${YELLOW}--- ENVIRONMENT SELECTION ---${NC}"
echo "1) Paid VPS (DigitalOcean, AWS, Hetzner)"
echo "2) CodeSandbox (Free - Forces Port 80)"
echo "3) GitHub Codespaces (Free - Forces Tunnel)"
echo ""
echo -n "Select your environment [1-3]: "
read ENV_TYPE

echo ""
echo -e "${YELLOW}--- COMPONENT SELECTION ---${NC}"
echo "1) Full Stack (Panel + Wings)"
echo "2) Wings Only"
echo "3) Panel Only"
echo ""
echo -n "Select install mode [1-3]: "
read INSTALL_MODE

# --- 4. CLEANUP & PREP ---
echo -e "${CYAN}[JAVIX]${NC} Cleaning up..."
rm -rf /var/www/pterodactyl /etc/pterodactyl /usr/local/bin/wings
# Ignore docker errors
docker rm -f $(docker ps -a -q) >/dev/null 2>&1

echo -e "${CYAN}[JAVIX]${NC} Installing Dependencies..."
# Install Docker
if ! command -v docker &> /dev/null; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash
fi
service docker start
# Install Database
apt-get install -y mariadb-server mariadb-client
service mariadb start

# --- 5. PANEL INSTALLATION ---
if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "3" ]; then
    echo -e "${CYAN}[JAVIX]${NC} Installing Panel..."
    
    # Database
    mysql -u root -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'javix123';"
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"

    # Files
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
    tar -xzvf panel.tar.gz
    chmod -R 755 storage bootstrap/cache

    # PHP & Composer
    apt-get install -y php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip}
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
    cp .env.example .env
    composer install --no-dev --optimize-autoloader --no-interaction
    php artisan key:generate --force

    # --- ENVIRONMENT CONFIG ---
    if [ "$ENV_TYPE" == "2" ]; then
        # CODESANDBOX LOGIC
        echo -e "${GREEN}Configuring for CodeSandbox (Port 80)...${NC}"
        sed -i "s|APP_URL=http://localhost|APP_URL=http://localhost|g" .env
        sed -i "s|APP_URL=https://panel.example.com|APP_URL=http://localhost|g" .env
        sed -i 's/DB_PASSWORD=/DB_PASSWORD=javix123/g' .env
        
        # Kill anything on port 80 and start
        fuser -k 80/tcp >/dev/null 2>&1
        nohup php artisan serve --host=0.0.0.0 --port=80 > panel.log 2>&1 &
        FQDN="localhost"
    
    elif [ "$ENV_TYPE" == "1" ]; then
        # PAID VPS LOGIC
        echo -e "${YELLOW}Enter your Domain (FQDN):${NC}"
        read FQDN
        sed -i "s|APP_URL=http://localhost|APP_URL=https://${FQDN}|g" .env
        php artisan p:environment:setup --author=admin@javix.com --url=https://$FQDN --timezone=UTC --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379
    fi

    # Finalize
    php artisan migrate --seed --force
    php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1
fi

# --- 6. WINGS INSTALLATION ---
if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "2" ]; then
    echo -e "${CYAN}[JAVIX]${NC} Installing Wings..."
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64"
    chmod u+x /usr/local/bin/wings
fi

# --- 7. FINAL OUTPUT ---
logo
echo "=========================================="
echo "      INSTALLATION COMPLETE"
echo "=========================================="
if [ "$ENV_TYPE" == "2" ]; then
    echo "MODE: CodeSandbox (Port 80)"
    echo "1. Look at 'PORTS' tab -> Port 80 should be there."
    echo "2. Create Node FQDN: localhost"
else
    echo "MODE: Standard"
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
    wings --debug > wings.log 2>&1 &
    echo -e "${GREEN}SUCCESS! Wings is running.${NC}"
fi
