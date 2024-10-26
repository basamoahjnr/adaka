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

# Network utility for fetching with retries
fetch_with_retry() {
  local url="$1"
  local output_path="$2"
  local retries=3
  local attempt=0
  local success=0

  while (( attempt < retries )); do
    feedback "Fetching $url (Attempt: $((attempt + 1))/$retries)"
    curl -o "$output_path" -s --max-time 10 "$url" && success=1 && break
    ((attempt++))
    sleep 2
  done

  (( success == 1 )) || error_exit "Failed to fetch $url after $retries attempts."
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
    
    # Run the Docker command
    docker run --rm -v "$volume" "$image" $command && return 0

    ((attempt++))
    sleep 2
  done

  return 1  # Indicate failure after retries
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
    local formatted_subnet="${BASH_REMATCH[1]}.x"
    echo "$formatted_subnet"
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

    feedback "Installing Docker and Docker Compose"
    sudo apt-get update || error_exit "Failed to update package list."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || error_exit "Failed to install Docker and Docker Compose."
  else
    error_exit "Exiting script as per user choice."
  fi
fi


# Generate bcrypt hash for the provided WG-Easy password
generate_and_escape_bcrypt_hash(){
  local password="$1"
  local bcrypt_hash=$(docker run --rm python:3-alpine sh -c \
    "pip install bcrypt > /dev/null 2>&1 && python3 -c 'import bcrypt; print(bcrypt.hashpw(b\"$password\", bcrypt.gensalt()).decode())'") || { return 1; }

  if [ -z "$bcrypt_hash" ]; then
    return 1
  fi

  # Repeat dollar signs without escaping them
  echo "$bcrypt_hash" | sed 's/\$/$$/g'
}


# Function to escape special characters in a string for use in sed
escape_for_sed() {
  local input="$1"
  echo "$input" | sed -e 's/[\/&]/\\&/g' -e 's/[][^.*$(){}+?|]/\\&/g'
}

# Options parsing
while getopts 'p:s:u:t:' OPTION; do 
  case "$OPTION" in    
    p) USER_PROVIDED_ADAKA_PASSWORD="$OPTARG" ;;
    s) USER_PROVIDED_ADAKA_DEFAULT_NETWORK="$OPTARG" ;;
    u) USER_PROVIDED_WGEASY_DEFAULT_NETWORK="$OPTARG" ;;
    t) USER_PROVIDED_ADAKA_DEFAULT_TZ="$OPTARG" ;;
    m) USER_PROVIDED_ADAKA_DIR="$OPTARG" ;;
    ?) 
      echo "Usage: $(basename $0) [-p password] [-s ADAKA subnet] [-u wg-easy client subnet] [-t timezone] [-m install path]" >&2      
      exit 1      
      ;;  
  esac
done
shift "$(($OPTIND -1))"

# Password is mandatory
[[ -z "$USER_PROVIDED_ADAKA_PASSWORD" ]] && { echo "Error: The password option (-p) must be provided." >&2; exit 1; }

# Validate IPs and subnets
feedback "Validating IPs and subnets"
[[ -n "$USER_PROVIDED_ADAKA_DEFAULT_NETWORK" ]] && validate_subnet "$USER_PROVIDED_ADAKA_DEFAULT_NETWORK"
[[ -n "$USER_PROVIDED_WGEASY_DEFAULT_NETWORK" ]] && validate_subnet "$USER_PROVIDED_WGEASY_DEFAULT_NETWORK"


# Set defaults
feedback "Setting ADAKA default values"
# Use provided values or fall back to defaults
ADAKA_DIR=${USER_PROVIDED_ADAKA_DIR:-$ADAKA_DIR} || error_exit "Failed to create install path"  
echo -e "${GREEN}ADAKA instal path set.${RESET}"

WGEASY_PASSWORD=$(generate_and_escape_bcrypt_hash "$USER_PROVIDED_ADAKA_PASSWORD") || error_exit "Failed to create wg-easy password"
echo -e "${GREEN}Wgeasy password set.${RESET}"


ADAKA_DEFAULT_NETWORK=${USER_PROVIDED_ADAKA_DEFAULT_NETWORK:-$ADAKA_DEFAULT_NETWORK}
echo -e "${GREEN}ADAKA network set to $ADAKA_DEFAULT_NETWORK${RESET}"

ADAKA_DEFAULT_TZ=${USER_PROVIDED_ADAKA_DEFAULT_TZ:-$ADAKA_DEFAULT_TZ}
echo -e "${GREEN}ADAKA timezone set to $ADAKA_DEFAULT_TZ${RESET}"

WGEASY_DEFAULT_NETWORK=$(format_wg_easy_subnet "${USER_PROVIDED_WGEASY_DEFAULT_NETWORK:-$WGEASY_DEFAULT_NETWORK}") || error_exit "Failed to format WireGuard subnet."
echo -e "${GREEN}ADAKA WireGuard clients network set to $WGEASY_DEFAULT_NETWORK/24${RESET}"

ADAKA_PUBLIC_IP=$(curl -s ifconfig.me) || error_exit "Failed to retrieve public IP address."
echo -e "${GREEN}Public IP set to $ADAKA_PUBLIC_IP${RESET}"

PIHOLE_WEBPASSWORD=$(escape_for_sed "$USER_PROVIDED_ADAKA_PASSWORD") || error_exit "Failed to create pihole web interface password" 
echo -e "${GREEN}Pihole web password set. ${RESET}"

echo -e "${GREEN}Completed setting ADAKA default values.${RESET}"


# Create necessary directories
feedback "Creating necessary directories"
create_dir "$ADAKA_DIR"
create_dir "$WG_DIR"
create_dir "$PIHOLE_DIR/etc-pihole"
create_dir "$PIHOLE_DIR/etc-dnsmasq.d"
create_dir "$UNBOUND_DIR"
echo -e "${GREEN}Directories created successfully.${RESET}"



# Fetch root hints for Unbound with retries
feedback "Fetching root hints for Unbound"
fetch_with_retry "https://www.internic.net/domain/named.root" "$UNBOUND_DIR/root.hints"
echo -e "${GREEN}Root hints downloaded successfully.${RESET}"

# Fetch DNSSEC root trust anchor
feedback "Fetching DNSSEC root trust anchor"
run_docker_with_retry "$UNBOUND_IMAGE" "$UNBOUND_DIR:/opt/unbound/etc/unbound" "unbound-anchor -a \"/opt/unbound/etc/unbound/root.key\"" \
|| error_exit "Failed to fetch DNSSEC root trust anchor."
echo -e "${GREEN}DNSSEC root trust anchor fetched successfully.${RESET}"

# Create Unbound config from template
echo "Configuring Unbound from template..."
awk -v adaka_network="$ADAKA_DEFAULT_NETWORK" \
    '{gsub("{{ADAKA_DEFAULT_NETWORK}}", adaka_network);
      print}' $(pwd)/.unbound.conf.template > $UNBOUND_DIR/unbound.conf

# replace_placeholders ".unbound.conf.template" "$UNBOUND_DIR/unbound.conf" 
echo -e "${GREEN}Unbound configuration file successfully created from template.${RESET}"

# Create Docker Compose config from template
echo "Configuring Docker Compose from template..."
# Create Docker Compose config from template using sed
feedback "Configuring Docker Compose from template"
sed -e "s|{{ADAKA_DEFAULT_NETWORK}}|$ADAKA_DEFAULT_NETWORK|g" \
    -e "s|{{PUBLIC_IP}}|$ADAKA_PUBLIC_IP|g" \
    -e "s|{{WGEASY_IMAGE}}|$WGEASY_IMAGE|g" \
    -e "s|{{WGEASY_PASSWORD}}|$WGEASY_PASSWORD|g" \
    -e "s|{{WGEASY_DEFAULT_NETWORK}}|$WGEASY_DEFAULT_NETWORK|g" \
    -e "s|{{PIHOLE_IMAGE}}|$PIHOLE_IMAGE|g" \
    -e "s|{{PIHOLE_WEBPASSWORD}}|$PIHOLE_WEBPASSWORD|g" \
    -e "s|{{ADAKA_DEFAULT_TZ}}|$ADAKA_DEFAULT_TZ|g" \
    -e "s|{{UNBOUND_IMAGE}}|$UNBOUND_IMAGE|g" \
    -e "s|{{PIHOLE_SECONDARY_DNS_SERVER}}|$PIHOLE_SECONDARY_DNS_SERVER|g" \
    "$(pwd)/.docker-compose.yml.template" > "$ADAKA_DIR/docker-compose.yml" || error_exit "Failed to create Docker Compose file."


# replace_placeholders ".docker-compose.yml.template" "$ADAKA_DIR/docker-compose.yml"
echo -e "${GREEN}Docker Compose file successfully created from template.${RESET}"

# Setup for Docker Compose
feedback "Starting up the Docker Compose setup"
docker compose -f "$ADAKA_DIR/docker-compose.yml" -p adaka down || error_exit "Failed to stop existing Docker containers."
docker compose -f "$ADAKA_DIR/docker-compose.yml" -p adaka up -d || error_exit "Failed to start Docker Compose setup."

# Output the setup completion message
echo -e "\n\n\n${GREEN}Setup complete! Pi-hole, WireGuard, and Unbound are now running.${RESET}"
echo -e "Pi-hole is running at: ${GREEN}http://$ADAKA_PUBLIC_IP:5353/admin${RESET} or ${GREEN}http://10.8.0.3:5353/admin${RESET}"
echo -e "Wg-easy is running at: ${GREEN}http://$ADAKA_PUBLIC_IP:51821${RESET} or ${GREEN}http://10.8.0.2:51821${RESET}"
echo -e "\n${RED}REMEMBER TO:${RESET} Configure Pi-hole to use 127.0.0.1#5335 as the Custom DNS."
