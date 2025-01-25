#!/bin/bash
# Constants for colors
GREEN="\033[0;32m"
RESET="\033[0m"
RED="\033[0;31m"
CYAN="\033[0;36m"

# Load variables from config file
source .config.sh || error_exit "Failed to load configuration file."

# Utility function to exit with an error message
error_exit() {
  echo -e "${RED}Error: $1${RESET}" >&2
  exit 1
}

# Colored feedback utility
feedback() {
  echo -e "${CYAN}$1...${RESET}"
}

# Directory creation utility with error handling
create_dir() {
  local dir_path="$1"
  feedback "Creating directory: $dir_path"
  mkdir -p "$dir_path" || error_exit "Failed to create directory: $dir_path"
}


convert_network_to_wgeasy_format() {
    local network="$1"
    local base_ip="${network%/*}"
    local ip_prefix="${base_ip%.*}"

    echo "${ip_prefix}.x"
}


# Network utility for fetching with retries
fetch_with_retry() {
    local url="$1"
    local output_path="$2"
    local retries=3
    local attempt=0

    while (( attempt < retries )); do
        feedback "Fetching $url (Attempt: $((attempt + 1))/$retries)"
        curl -o "$output_path" -s --fail --max-time 10 "$url" && return 0
        ((attempt++))
        sleep 2
    done

    error_exit "Failed to fetch $url after $retries attempts."
}

# Function to run Docker command with retries
run_docker_with_retry() {
    local image="$1"
    local volume="$2"
    local command="$3"
    local retries=3
    local attempt=0

    while (( attempt < retries )); do
        feedback "Running Docker command (Attempt: $((attempt + 1))/$retries)"
        docker run --rm -v "$volume" "$image" sh -c "$command" && return 0 # Modified to use sh -c
        ((attempt++))
        sleep 2
    done

    error_exit "Failed to run Docker command after $retries attempts."
}

# Validate IP Address format
validate_ip() {
  local ip="$1"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || error_exit "Invalid IP format: $ip"
}

# Validate Subnet format (CIDR)
validate_subnet() {
  local subnet="$1"
  [[ "$subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]] || error_exit "Invalid subnet format: $subnet"
}

# Validate and format subnet for wg-easy
format_wg_easy_subnet() {
  local subnet="$1"
  if [[ "$subnet" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/[0-9]+$ ]]; then
    echo "${BASH_REMATCH[1]}.x"
  else
    error_exit "Invalid subnet format: $subnet. Ensure it follows a valid IP/CIDR format."
  fi
}

# Check and install Docker and Docker Compose if missing
feedback "Checking for Docker and Docker Compose"
if ! (docker --version && (docker-compose --version || docker compose version)); then
  echo -e "${RED}Docker or Docker Compose is not installed.${RESET}"
  read -p "Do you want to install Docker and Docker Compose? (y/n): " install_choice

  if [[ "$install_choice" =~ ^[Yy]$ ]]; then
    feedback "Removing conflicting packages"
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
      sudo apt-get remove -y "$pkg" || error_exit "Failed to remove conflicting package: $pkg"
    done

    feedback "Adding Docker repository"
    sudo apt-get update || error_exit "Failed to update package list."
    sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common || error_exit "Failed to install prerequisites."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg || error_exit "Failed to add Docker GPG key."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || error_exit "Failed to add Docker repository."

    feedback "Installing Docker"
    sudo apt-get update || error_exit "Failed to update package list."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose || error_exit "Failed to install Docker."

    feedback "Installing both old and new Docker Compose versions"
    sudo apt-get install -y docker-compose-plugin || error_exit "Failed to install new Docker Compose plugin."
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose || error_exit "Failed to download old Docker Compose."
    sudo chmod +x /usr/local/bin/docker-compose || error_exit "Failed to set permissions for docker-compose."

    feedback "Both old and new Docker Compose versions installed successfully."
  else
    error_exit "Exiting script as per user choice."
  fi
fi


feedback "Checking Docker Compose installation"
if ! command -v docker-compose &> /dev/null; then
  feedback "docker-compose command not found. Checking for alternate Docker Compose installation."
  if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    feedback "Switching to the new 'docker compose' syntax as docker-compose is missing."
    alias docker-compose="docker compose"
  else
    error_exit "Neither docker-compose nor the new Docker Compose plugin is installed. Install Docker Compose before proceeding."
  fi
fi

# Generate bcrypt hash for the provided WG-Easy password
generate_and_escape_bcrypt_hash() {
  local password="$1"
  local bcrypt_hash
  bcrypt_hash=$(docker run --rm python:3-alpine sh -c \
    "pip install bcrypt > /dev/null 2>&1 && python3 -c 'import bcrypt; print(bcrypt.hashpw(b\"$password\", bcrypt.gensalt()).decode())'") || error_exit "Failed to generate bcrypt hash."

  echo "$bcrypt_hash" | sed 's/\$/\$\$/g'
}

# Options parsing
ADAKA_PASSWORD="" # Initialize the variable
WGEASY_DNS="" # Initialize the variable
while getopts 'p:n:' OPTION; do
  case "$OPTION" in
    p) ADAKA_PASSWORD="$OPTARG" ;;
    n) WGEASY_DNS="$OPTARG" ;;
    \?)
      echo "Usage: $(basename "$0") -p password -n [pihole|adguard]" >&2
      exit 1
      ;;
  esac
done

shift "$((OPTIND - 1))"

# Check if the password was provided
if [ -z "$ADAKA_PASSWORD" ]; then
  echo "Error: The -p option (password) is required." >&2
  echo "Usage: $(basename "$0") -p password" >&2
  exit 1
fi

feedback "Validating IPs and subnets"
[[ -n "$ADAKA_NETWORK" ]] && validate_subnet "$ADAKA_NETWORK"
[[ -n "$WGEASY_NETWORK" ]] && validate_subnet "$WGEASY_NETWORK"

feedback "Setting ADAKA default values"
ADAKA_DIR=${ADAKA_DIR:-$(mkdir -p "$HOME/adaka")}
feedback "ADAKA install path set to $ADAKA_DIR"

ADAKA_NETWORK=${ADAKA_NETWORK:-$ADAKA_DEFAULT_NETWORK}
feedback "ADAKA network set to $ADAKA_NETWORK"

ADAKA_TZ=${ADAKA_TZ:-$(cat /etc/timezone)}
feedback "ADAKA timezone set to $ADAKA_TZ"

WGEASY_NETWORK="${WGEASY_NETWORK:-$WGEASY_DEFAULT_NETWORK}"
feedback "ADAKA WireGuard clients network set to $WGEASY_NETWORK"

WGEASY_DNS="${WGEASY_DNS:-$WGEASY_DEFAULT_DNS}"
if [ "$WGEASY_DNS" = "pihole" ]; then
  WGEASY_DNS="$PIHOLE_IPV4_ADDRESS"
else
  WGEASY_DNS="$ADGUARD_IPV4_ADDRESS"
fi
feedback "ADAKA WireGuard default dns set to $WGEASY_DNS"

ADAKA_PUBLIC_IP=$(curl -s ifconfig.me) || error_exit "Failed to retrieve public IP address."
feedback "Public IP set to $ADAKA_PUBLIC_IP"

WGEASY_NETWORK=$(convert_network_to_wgeasy_format "$WGEASY_NETWORK")
feedback "WG-Easy network set to $WGEASY_NETWORK"


# Set Pi-hole password
PIHOLE_WEBPASSWORD="${PIHOLE_WEBPASSWORD:-$ADAKA_PASSWORD}"
PIHOLE_WEBPASSWORD=$(printf '%s\n' "$PIHOLE_WEBPASSWORD" | sed -e 's/[\/&]/\\&/g' -e 's/[][$^.*|{}]/\\&/g')
feedback "pihole password set"

# Set Adgurad password
ADGUARD_WEBPASSWORD="${ADGUARD_WEBPASSWORD:-$ADAKA_PASSWORD}"
ADGUARD_WEBPASSWORD=$(printf '%s\n' "$ADGUARD_WEBPASSWORD" | sed -e 's/[\/&]/\\&/g' -e 's/[][$^.*|{}]/\\&/g')
feedback "Adgurad password set"


# Set Portainer password
PORTAINER_WEBPASSWORD="${PORTAINER_WEBPASSWORD:-$ADAKA_PASSWORD}"
PORTAINER_WEBPASSWORD=$(printf '%s\n' "$PORTAINER_WEBPASSWORD" | sed -e 's/[\/&]/\\&/g' -e 's/[][$^.*|{}]/\\&/g')
feedback "Portainer passwrod set"

WGEASY_PASSWORD=$(generate_and_escape_bcrypt_hash "$ADAKA_PASSWORD") || error_exit "Failed to create WG-Easy password."
feedback "WG-Easy password set successfully."

feedback "Creating necessary directories"
mkdir -p "$ADAKA_DIR" || error_exit "Failed to create ADAKA directory at $ADAKA_DIR"
mkdir -p "$WGEASY_DIR" || error_exit "Failed to create WG-Easy directory at $WGEASY_DIR"
mkdir -p "$PIHOLE_DIR/etc-pihole" || error_exit "Failed to create Pi-hole directory at $PIHOLE_DIR/etc-pihole"
mkdir -p "$PIHOLE_DIR/etc-dnsmasq.d" || error_exit "Failed to create Pi-hole directory at $PIHOLE_DIR/etc-dnsmasq.d"
mkdir -p "$ADGUARD_DIR" || error_exit "Failed to create AdGuard directory at $ADGUARD_DIR"
mkdir -p "$UNBOUND_DIR" || error_exit "Failed to create Unbound directory at $UNBOUND_DIR"
mkdir -p "$PORTAINER_DIR" || error_exit "Failed to create Portainer directory at $PORTAINER_DIR"
feedback "Directories created successfully."

fetch_with_retry "https://www.internic.net/domain/named.root" "$UNBOUND_DIR/root.hints"
feedback "Root hints downloaded successfully."

# Download root.key before running unbound-anchor
feedback "Fetching DNSSEC root trust anchor"
run_docker_with_retry "$UNBOUND_IMAGE" "$UNBOUND_DIR:/opt/unbound/etc/unbound" "unbound-anchor -a /opt/unbound/etc/unbound/root.key" # Fixed command
feedback "DNSSEC root trust anchor fetched successfully."



feedback "Configuring Unbound from template"
sed -e "s|{{ADAKA_NETWORK}}|$ADAKA_NETWORK|g" ".unbound.conf.template" > "$UNBOUND_DIR/unbound.conf" || error_exit "Failed to stop existing Docker containers."
feedback "Unbound configuration file successfully created from template."

feedback "Configuring Docker Compose from template"
sed -e "s|{{ADAKA_NETWORK}}|$ADAKA_NETWORK|g" \
    -e "s|{{ADAKA_TZ}}|$ADAKA_TZ|g" \
    -e "s|{{PUBLIC_IP}}|$ADAKA_PUBLIC_IP|g" \
    -e "s|{{WGEASY_IMAGE}}|$WGEASY_IMAGE|g" \
    -e "s|{{WGEASY_PASSWORD}}|$WGEASY_PASSWORD|g" \
    -e "s|{{WGEASY_DIR}}|$WGEASY_DIR|g" \
    -e "s|{{WGEASY_DNS}}|$WGEASY_DNS|g" \
    -e "s|{{WGEASY_NETWORK}}|$WGEASY_NETWORK|g" \
    -e "s|{{WGEASY_IPV4_ADDRESS}}|$WGEASY_IPV4_ADDRESS|g" \
    -e "s|{{PIHOLE_IMAGE}}|$PIHOLE_IMAGE|g" \
    -e "s|{{PIHOLE_WEBPASSWORD}}|$PIHOLE_WEBPASSWORD|g" \
    -e "s|{{PIHOLE_DIR}}|$PIHOLE_DIR|g" \
    -e "s|{{PIHOLE_IPV4_ADDRESS}}|$PIHOLE_IPV4_ADDRESS|g" \
    -e "s|{{ADGUARD_IMAGE}}|$ADGUARD_IMAGE|g" \
    -e "s|{{ADGUARD_WEBPASSWORD}}|$ADGUARD_WEBPASSWORD|g" \
    -e "s|{{ADGUARD_DIR}}|$ADGUARD_DIR|g" \
    -e "s|{{ADGUARD_IPV4_ADDRESS}}|$ADGUARD_IPV4_ADDRESS|g" \
    -e "s|{{UNBOUND_IMAGE}}|$UNBOUND_IMAGE|g" \
    -e "s|{{UNBOUND_DIR}}|$UNBOUND_DIR|g" \
    -e "s|{{UNBOUND_IPV4_ADDRESS}}|$UNBOUND_IPV4_ADDRESS|g" \
    -e "s|{{PORTAINER_WEBPASSWORD}}|$PORTAINER_WEBPASSWORD|g" \
    -e "s|{{PORTAINER_IMAGE}}|$PORTAINER_IMAGE|g" \
    -e "s|{{PORTAINER_DIR}}|$PORTAINER_DIR|g" \
    -e "s|{{PORTAINER_IPV4_ADDRESS}}|$PORTAINER_IPV4_ADDRESS|g" \
    ".docker-compose.yml.template" > "$ADAKA_DIR/docker-compose.yml" || error_exit "Failed to create Docker Compose file."
feedback "Docker Compose file successfully created from template."


docker compose -f "$ADAKA_DIR/docker-compose.yml" -p adaka down || error_exit "Failed to stop existing Docker containers."
docker compose -f "$ADAKA_DIR/docker-compose.yml" -p adaka up -d || error_exit "Failed to start Docker Compose setup."

feedback "Setup complete! Pi-hole, WireGuard, and Unbound are now running."
echo -e "Pi-hole is running at: ${GREEN}http://$ADAKA_PUBLIC_IP:5353/admin${RESET} or ${GREEN}http://10.8.0.3:5353/admin${RESET}"
echo -e "Wg-easy is running at: ${GREEN}http://$ADAKA_PUBLIC_IP:51821${RESET} or ${GREEN}http://10.8.0.2:51821${RESET}"
echo -e "${RED}REMEMBER TO:${RESET} Configure Pi-hole to use 127.0.0.1#5335 as the Custom DNS."
