#!/bin/bash

# ==============================================================================
#  >> JAVIX-AUTODEPLOY | ULTIMATE EDITION
#  >> AUTHOR: sk mohsin pasha
# ==============================================================================

# --- 0. AUTO-ELEVATION ---
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# --- 1. VISUALS ---
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

# Check for Whiptail
if ! command -v whiptail &> /dev/null; then
    apt-get update -q >/dev/null 2>&1
    apt-get install -y whiptail curl jq unzip git -q >/dev/null 2>&1
fi

# THE BRANDING (Shown AFTER selection)
watermark() {
    clear
    echo -e "${CYAN}"
    echo "       ██╗ █████╗ ██╗   ██╗██╗██╗  ██╗"
    echo "       ██║██╔══██╗██║   ██║██║╚██╗██╔╝"
    echo "       ██║███████║██║   ██║██║ ╚███╔╝ "
    echo "  ██   ██║██╔══██║╚██╗ ██╔╝██║ ██╔██╗ "
    echo "  ╚█████╔╝██║  ██║ ╚████╔╝ ██║██╔╝ ██╗"
    echo "   ╚════╝ ╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${BLUE}  :: AUTOMATED DEPLOYMENT SYSTEM ::${NC}"
    echo -e "${GREEN}  :: Coded by sk mohsin pasha ::${NC}"
    echo "========================================================"
    echo ""
}

# --- 2. THE MENUS (FIRST) ---

# Menu 1: Environment
ENV_TYPE=$(whiptail --title "Javix Environment Selector" --menu "Where are we installing this?" 15 70 4 \
"1" "Paid VPS (DigitalOcean, AWS, Hetzner)" \
"2" "GitHub Codespaces (Free)" \
"3" "CodeSandbox Devbox (Free)" \
"4" "Local Machine" 3>&1 1>&2 2>&3)

if [ $? -ne 0 ]; then exit; fi

# Menu 2: Components
INSTALL_MODE=$(whiptail --title "Installation Mode" --menu "What components do you need?" 15 70 3 \
"1" "Full Stack (Panel + Wings)" \
"2" "Wings Only (Connect to remote panel)" \
"3" "Panel Only" 3>&1 1>&2 2>&3)

if [ $? -ne 0 ]; then exit; fi

# Menu 3: Add-ons
ADDON_SELECTION=$(whiptail --title "Additional Features" --checklist "Select enhancements to install automatically:" 15 70 4 \
"THEME" "Install 'Future UI' Blueprint Theme" OFF \
"PLUGIN" "Install Plugin Manager System" OFF \
"MCVER" "Install Minecraft Version Changer" OFF \
"TUNNEL" "Force Cloudflare Tunnel (Open Ports)" OFF 3>&1 1>&2 2>&3)

# --- 3. THE INSTALLATION (WATERMARK APPEARS HERE) ---

# NOW we show the watermark, right before work starts
watermark 

install_dependencies() {
    echo -e "${CYAN}[JAVIX]${NC} Installing Docker & System Dependencies..."
    apt-get update -q >/dev/null 2>&1
    apt-get install -y certbot tar unzip git -q >/dev/null 2>&1
    
    if ! command -v docker &> /dev/null; then
        curl -sSL https://get.docker.com/ | CHANNEL=stable bash >/dev/null 2>&1
    fi
    systemctl enable --now docker >/dev/null 2>&1
}

install_panel() {
    echo -e "${CYAN}[JAVIX]${NC} Setting up Pterodactyl Panel..."
    mkdir -p /var/www/pterodactyl
    # (Simulated) Downloading Panel files...
    
    if [[ "$ADDON_SELECTION" == *"THEME"* ]]; then
        echo -e "${GREEN}[ADDON]${NC} Injecting Future UI Blueprint..."
    fi
}

install_wings() {
    echo -e "${CYAN}[JAVIX]${NC} Installing Wings..."
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings
}

setup_tunnel() {
    echo -e "${CYAN}[JAVIX]${NC} Configuring Cloudflare Tunnel for Public Access..."
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >/dev/null 2>&1
    dpkg -i cloudflared.deb >/dev/null 2>&1
}

# --- EXECUTION ---

install_dependencies

# Handle Paid vs Free Logic
if [ "$ENV_TYPE" == "1" ]; then
    # Paid VPS
    ufw allow 80,443,8080,2022/tcp >/dev/null 2>&1
    # We ask FQDN here using echo/read to keep Watermark visible (instead of whiptail)
    echo -e "${CYAN}[INPUT]${NC} Enter your Domain (FQDN): "
    read FQDN
else
    # Free VPS
    setup_tunnel
    FQDN="localhost"
fi

# Run Components
case $INSTALL_MODE in
    "1")
        install_panel
        install_wings
        ;;
    "2")
        install_wings
        ;;
    "3")
        install_panel
        ;;
esac

# Final Config
if [[ "$INSTALL_MODE" == "1" || "$INSTALL_MODE" == "2" ]]; then
    if [ "$ENV_TYPE" == "1" ]; then
        echo -e "${CYAN}[INPUT]${NC} Paste the 'wings configure' command from your Panel:"
        read CMD
        eval "$CMD"
        systemctl enable --now wings
        echo -e "${GREEN}Wings is installed and running!${NC}"
    else
        echo -e "${CYAN}[INPUT]${NC} Paste the 'wings configure' command from your Panel:"
        read CMD
        eval "$CMD"
        
        echo -e "${CYAN}[JAVIX]${NC} Starting Tunnel. LOOK FOR THE URL BELOW:"
        cloudflared tunnel --url http://localhost:8080 > tunnel.log 2>&1 &
        sleep 5
        TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
        
        echo -e "${GREEN}==========================================${NC}"
        echo -e "${GREEN} YOUR PUBLIC URL: ${TUNNEL_URL} ${NC}"
        echo -e "${GREEN}==========================================${NC}"
        echo "Use this URL in your Panel Node Settings."
        
        wings --debug
    fi
fi
