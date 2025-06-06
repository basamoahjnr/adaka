#!/bin/bash

# =============================================================================
# Configuration and Constants
# =============================================================================

# Load configuration with validation
CONFIG_FILE=".config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "\033[0;31mError: Missing configuration file $CONFIG_FILE\033[0m" >&2
    exit 1
fi
source "$CONFIG_FILE" || exit 1

# Color constants
GREEN="\033[0;32m"
RED="\033[0;31m"
CYAN="\033[0;36m"
RESET="\033[0m"

# =============================================================================
# Core Functions
# =============================================================================

# Exit with error message
error_exit() {
    echo -e "${RED}Error: $1${RESET}" >&2
    exit 1
}

# Colored status messages
feedback() {
    echo -e "${CYAN}==> $1...${RESET}"
}

# Validate CIDR subnet format
validate_subnet() {
    local subnet="$1"
    if [[ ! "$subnet" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        error_exit "Invalid subnet: $subnet. Use CIDR format (e.g. 192.168.1.0/24)"
    fi
    
    # Enforce /24 subnet for WireGuard compatibility
    local cidr="${subnet#*/}"
    if [[ "$cidr" -ne 24 ]]; then
        error_exit "WireGuard network must be /24. Given: $subnet"
    fi
}

# Convert CIDR to WireGuard format (xxx.xxx.xxx.x)
convert_wg_network() {
    local network="$1"
    if [[ "$network" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\.0/[0-9]{1,2}$ ]]; then
        echo "${BASH_REMATCH[1]}.x"
    else
        error_exit "Network conversion failed: $network"
    fi
}

# Install Docker and Compose if missing
install_dependencies() {
    feedback "Checking Docker installation"
    if ! command -v docker &> /dev/null; then
        feedback "Installing Docker ecosystem"
        
        # Remove conflicting packages
        for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
            sudo apt-get remove -y "$pkg" 2>/dev/null
        done

        # Set up Docker repository
        sudo apt-get update
        sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker components
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io

        # Install Docker Compose versions
        sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        sudo apt-get install -y docker-compose-plugin
    fi
}

# Create directory structure with secure permissions
setup_directories() {
    local dirs=(
        "$ADAKA_DIR"
        "$WGEASY_DIR"
        "$PIHOLE_DIR/etc-pihole" 
        "$PIHOLE_DIR/etc-dnsmasq.d"
        "$ADGUARD_DIR"
        "$UNBOUND_DIR"
        "$PORTAINER_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            feedback "Creating directory: $dir"
            mkdir -p "$dir" || error_exit "Failed to create $dir"
            chmod 700 "$dir"  # Restrict permissions
        fi
    done
}

# Generate bcrypt hash for WG-Easy password
generate_bcrypt_hash() {
    local password="$1"
    docker run --rm python:3-alpine sh -c \
        "pip install bcrypt >/dev/null 2>&1 && python3 -c 'import bcrypt; print(bcrypt.hashpw(b\"$password\", bcrypt.gensalt()).decode())'" \
        | sed 's/\$/\$\$/g'  # Escape $ for sed
}

# Retry wrapper for network operations
fetch_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local attempt=0

    while (( attempt < max_retries )); do
        feedback "Downloading $url (Attempt $((attempt+1))/$max_retries)"
        if curl -sSf --max-time 10 -o "$output" "$url"; then
            return 0
        fi
        ((attempt++))
        sleep 2
    done

    error_exit "Failed to download $url after $max_retries attempts"
}

# Configure Unbound services
configure_unbound() {
    feedback "Initializing Unbound configuration"
    
    # Download root hints
    fetch_with_retry "https://www.internic.net/domain/named.root" \
        "$UNBOUND_DIR/root.hints"
    feedback "Root hints downloaded successfully"

    # Initialize DNSSEC trust anchor
    feedback "Setting up DNSSEC root trust anchor"
    run_docker_with_retry "$UNBOUND_IMAGE" \
        "$UNBOUND_DIR:/opt/unbound/etc/unbound" \
        "unbound-anchor -a /opt/unbound/etc/unbound/root.key"
    feedback "DNSSEC trust anchor established"

    # Generate Unbound configuration
    feedback "Applying network settings to Unbound template"
    if [[ ! -f ".unbound.conf.template" ]]; then
        error_exit "Unbound template file missing"
    fi

    sed -e "s|{{ADAKA_NETWORK}}|$ADAKA_DEFAULT_NETWORK|g" \
        ".unbound.conf.template" > "$UNBOUND_DIR/unbound.conf" \
        || error_exit "Unbound configuration failed"


    feedback "Unbound configuration completed successfully"
}

# Docker command retry logic
run_docker_with_retry() {
    local image="$1"
    local volume="$2"
    local command="$3"
    local max_retries=3
    local attempt=0

    while (( attempt < max_retries )); do
        feedback "Executing Docker command (Attempt $((attempt+1))/$max_retries)"
        if docker run --rm -v "$volume" "$image" sh -c "$command"; then
            return 0
        fi
        ((attempt++))
        sleep 2
    done

    error_exit "Docker command failed after $max_retries attempts: $command"
}


# Generate Docker Compose configuration from template
generate_compose_config() {
    local template=".docker-compose.yml.template"
    local dns_template=".${WGEASY_DNS}.template"
    local dns_ip
    
    # Determine DNS service IP
    case "$WGEASY_DNS" in
        "pihole") dns_ip="$PIHOLE_IPV4_ADDRESS" ;;
        "adguard") dns_ip="$ADGUARD_IPV4_ADDRESS" ;;
        *) error_exit "Invalid DNS selection" ;;
    esac

    feedback "Generating Docker Compose configuration"
    
    # Validate template files
    [[ -f "$template" ]] || error_exit "Main template $template missing"
    [[ -f "$dns_template" ]] || error_exit "DNS template $dns_template missing"

    # Insert DNS service section
    sed -e "/{{DNS_SECTION}}/r $dns_template" \
        -e "/{{DNS_SECTION}}/d" \
        "$template" > "$ADAKA_DIR/docker-compose.yml.tmp" \
        || error_exit "Template processing failed"

    # Substitute all variables
    sed -i.bak \
        -e "s|{{ADAKA_NETWORK}}|$ADAKA_DEFAULT_NETWORK|g" \
        -e "s|{{ADAKA_DEFAULT_TZ}}|$ADAKA_DEFAULT_TZ|g" \
        -e "s|{{PUBLIC_IP}}|$ADAKA_PUBLIC_IP|g" \
        -e "s|{{WGEASY_IMAGE}}|$WGEASY_IMAGE|g" \
        -e "s|{{WGEASY_PASSWORD}}|$WGEASY_PASSWORD|g" \
        -e "s|{{WGEASY_DIR}}|$WGEASY_DIR|g" \
        -e "s|{{WGEASY_DNS}}|$dns_ip|g" \
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
        "$ADAKA_DIR/docker-compose.yml.tmp" \
        || error_exit "Variable substitution failed"

    # Finalize configuration
    mv "$ADAKA_DIR/docker-compose.yml.tmp" "$ADAKA_DIR/docker-compose.yml" \
        || error_exit "Final compose file move failed"
    rm -f "$ADAKA_DIR/docker-compose.yml.tmp.bak"
}

# =============================================================================
# Main Execution Flow
# =============================================================================

# Parse command-line options
while getopts 'p:n:' opt; do
    case "$opt" in
        p) ADAKA_PASSWORD="$OPTARG" ;;
        n) WGEASY_DNS="$OPTARG" ;;
        *) error_exit "Usage: $0 -p password -n [pihole|adguard]" ;;
    esac
done
shift "$((OPTIND-1))"

# Validate mandatory parameters
[[ -z "$ADAKA_PASSWORD" ]] && error_exit "Password required (-p)"
[[ "$WGEASY_DNS" =~ ^(pihole|adguard)$ ]] || error_exit "Invalid DNS option: $WGEASY_DNS"

# Set derived values
ADAKA_PUBLIC_IP=$(curl -4 -s ifconfig.me) || error_exit "Failed to get public IP"
WGEASY_NETWORK=$(convert_wg_network "$WGEASY_DEFAULT_NETWORK") || exit 1

# Install dependencies
install_dependencies

# Set up directory structure
setup_directories

# Configure Unbound components
configure_unbound  # Added critical section

# Process passwords
feedback "Configuring service credentials"
WGEASY_PASSWORD=$(generate_bcrypt_hash "$ADAKA_PASSWORD")
PIHOLE_WEBPASSWORD=$(printf '%s' "$ADAKA_PASSWORD" | sed 's/[\/&]/\\&/g')
ADGUARD_WEBPASSWORD=$(printf '%s' "$ADAKA_PASSWORD" | sed 's/[\/&]/\\&/g')
PORTAINER_WEBPASSWORD=$(printf '%s' "$ADAKA_PASSWORD" | sed 's/[\/&]/\\&/g')

# Generate Docker configuration
generate_compose_config

# Launch services
feedback "Launching application stack"
docker compose -f "$ADAKA_DIR/docker-compose.yml" -p adaka down --remove-orphans
docker compose -f "$ADAKA_DIR/docker-compose.yml" -p adaka up -d --force-recreate \
    || error_exit "Failed to start services"

# Success output
feedback "${GREEN}Deployment complete!${RESET}"
echo -e "WireGuard Admin: ${GREEN}http://$ADAKA_PUBLIC_IP:51821${RESET}"
echo -e "${WGEASY_DNS^} Admin: ${GREEN}http://$ADAKA_PUBLIC_IP:5353/admin${RESET}"
echo -e "Portainer: ${GREEN}http://$ADAKA_PUBLIC_IP:9000${RESET}"
echo -e "\n${RED}Important:${RESET} Configure ${WGEASY_DNS} to use Unbound at 127.0.0.1:5335"