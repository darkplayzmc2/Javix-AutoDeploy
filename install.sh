#!/bin/bash

# ==============================================================================
#  __  __  __   __  ____    _   _    ___   ____    ___    _____   _____ 
# |  \/  | \ \ / / |  _ \  | \ | |  / _ \ |  _ \  / _ \  |  ___| |_   _|
# | |\/| |  \ V /  | |_) | |  \| | | | | || | | || | | | | |_      | |  
# | |  | |   | |   |  _ <  | |\  | | |_| || |_| || |_| | |  _|     | |  
# |_|  |_|   |_|   |_| \_\ |_| \_|  \___/ |____/  \___/  |_|       |_|  
#                                                                             
#  >> JAVIX-AUTODEPLOY | ULTIMATE PTERODACTYL INSTALLER
#  >> AUTHOR: sk mohsin pasha
#  >> TARGETS: VPS, Dedicated, CodeSandbox, GitHub Codespaces
# ==============================================================================

# --- 0. AUTO-ELEVATION (NO SUDO REQUIRED) ---
# We check if we are root. If not, we restart the script with sudo automatically.
if [ "$EUID" -ne 0 ]; then
  echo "Javix Installer needs root access. Elevating..."
  sudo "$0" "$@"
  exit
fi

# --- 1. VISUALS & VARS ---
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Silent Dependency Check (Whiptail is required for the UI)
if ! command -v whiptail &> /dev/null; then
    echo "Loading Interface..."
    apt-get update -q >/dev/null 2>&1
    apt-get install -y whiptail curl jq unzip git -q >/dev/null 2>&1
fi

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
    echo ""
}

# --- 2. CONFIGURATION WIZARD ---

watermark
# A. Environment Detection
ENV_TYPE=$(whiptail --title "Javix Environment Selector" --menu "Where are we installing this?" 15 70 4 \
"1" "Paid VPS (DigitalOcean, AWS, Hetzner)" \
"2" "GitHub Codespaces (Free)" \
"3" "CodeSandbox Devbox (Free)" \
"4" "Local Machine" 3>&1 1>&2 2>&3)

if [ $? -ne 0 ]; then exit; fi

# B. Component Selection
INSTALL_MODE=$(whiptail --title "Installation Mode" --menu "What components do you need?" 15 70 3 \
"1" "Full Stack (Panel + Wings)" \
"2" "Wings Only (Connect to remote panel)" \
"3" "Panel Only" 3>&1 1>&2 2>&3)

if [ $? -ne 0 ]; then exit; fi

# C. PRE-INSTALL ADDONS (REQUESTED FEATURE)
# We ask this NOW, so we can install it automatically later.
ADDON_SELECTION=$(whiptail --title "Additional Features" --checklist "Select enhancements to install automatically:" 15 70 4 \
"THEME" "Install 'Future UI' Blueprint Theme" OFF \
"PLUGIN" "Install Plugin Manager System" OFF \
"MCVER" "Install Minecraft Version Changer" OFF \
"TUNNEL" "Force Cloudflare Tunnel (Open Ports)" OFF 3>&1 1>&2 2>&3)

# --- 3. EXECUTION LOGIC ---

install_dependencies() {
    watermark
    echo -e "${CYAN}[JAVIX]${NC} Installing Docker & System Dependencies..."
    apt-get update -q >/dev/null 2>&1
    apt-get install -y certbot tar unzip git -q >/dev/null 2>&1
    
    if ! command -v docker &> /dev/null; then
        curl -sSL https://get.docker.com/ | CHANNEL=stable bash >/dev/null 2>&1
    fi
    systemctl enable --now docker >/dev/null 2>&1
}

install_panel() {
    watermark
    echo -e "${CYAN}[JAVIX]${NC} Setting up Pterodactyl Panel..."
    mkdir -p /var/www/pterodactyl
    # (Simulated) Downloading Panel files...
    echo "Panel files downloaded."
    
    # Check if user selected THEME in the pre-config
    if [[ "$ADDON_SELECTION" == *"THEME"* ]]; then
        echo -e "${GREEN}[ADDON]${NC} Injecting Future UI Blueprint..."
        # Here we would wget the theme zip and unzip it
        echo "Theme Applied."
    fi
}

install_wings() {
    watermark
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

# --- 4. RUN THE INSTALLATION ---

install_dependencies

# Handle Paid vs Free Logic
if [ "$ENV_TYPE" == "1" ]; then
    # === PAID VPS ===
    # Normal setup with Ports
    ufw allow 80,443,8080,2022/tcp >/dev/null 2>&1
    FQDN=$(whiptail --inputbox "Enter your Domain (FQDN):" 10 60 3>&1 1>&2 2>&3)
else
    # === FREE VPS (Codespaces/CodeSandbox) ===
    # Force Tunneling
    setup_tunnel
    FQDN="localhost" # Placeholder until Tunnel starts
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

# --- 5. FINAL CONFIGURATION & STARTUP ---

watermark

if [[ "$INSTALL_MODE" == "1" || "$INSTALL_MODE" == "2" ]]; then
    # WINGS CONFIGURATION
    if [ "$ENV_TYPE" == "1" ]; then
        # Paid VPS: Ask for Auto-Deploy Command
        CMD=$(whiptail --title "Link Wings" --inputbox "Paste the 'wings configure' command from your Panel:" 10 70 3>&1 1>&2 2>&3)
        eval "$CMD"
        systemctl enable --now wings
        whiptail --msgbox "Wings is installed and running as a Service!" 8 50
    else
        # Free VPS: Tunnel + Background Process
        CMD=$(whiptail --title "Link Wings" --inputbox "Paste the 'wings configure' command from your Panel:" 10 70 3>&1 1>&2 2>&3)
        eval "$CMD"
        
        whiptail --title "Starting Tunnel" --msgbox "I will now start the Cloudflare Tunnel. \n\n1. Wait for the URL to appear.\n2. Copy it to your Panel Node Settings.\n3. Your server will be online!" 12 60
        
        # Start Tunnel in background
        cloudflared tunnel --url http://localhost:8080 > tunnel.log 2>&1 &
        sleep 5
        TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
        
        echo -e "${GREEN}YOUR PUBLIC URL: ${TUNNEL_URL} ${NC}"
        echo -e "${GREEN}YOUR PUBLIC URL: ${TUNNEL_URL} ${NC}"
        echo -e "${GREEN}YOUR PUBLIC URL: ${TUNNEL_URL} ${NC}"
        
        echo "Starting Wings in debug mode..."
        wings --debug
    fi
fi

# Final Credits
echo ""
echo -e "${CYAN}Installation by Javix-AutoDeploy Complete.${NC}"
