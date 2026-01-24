#!/bin/bash
set -euo pipefail

# =============================================================================
# Configuration and Constants
# =============================================================================

# Get script directory for relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration with validation
CONFIG_FILE="$SCRIPT_DIR/.config.sh"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "\033[0;31mError: Missing configuration file $CONFIG_FILE\033[0m" >&2
    exit 1
fi
source "$CONFIG_FILE" || exit 1

# Color constants
GREEN="\033[0;32m"
RED="\033[0;31m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
BOLD="\033[1m"
DIM="\033[2m"
RESET="\033[0m"

# Progress tracking
CURRENT_STEP=0
TOTAL_STEPS=8

# =============================================================================
# UI Helper Functions
# =============================================================================

# Print the welcome banner
print_banner() {
    echo -e "${CYAN}"
    echo "    ╔═══════════════════════════════════════════════════════════╗"
    echo "    ║                                                           ║"
    echo "    ║       █████╗ ██████╗  █████╗ ██╗  ██╗ █████╗             ║"
    echo "    ║      ██╔══██╗██╔══██╗██╔══██╗██║ ██╔╝██╔══██╗            ║"
    echo "    ║      ███████║██║  ██║███████║█████╔╝ ███████║            ║"
    echo "    ║      ██╔══██║██║  ██║██╔══██║██╔═██╗ ██╔══██║            ║"
    echo "    ║      ██║  ██║██████╔╝██║  ██║██║  ██╗██║  ██║            ║"
    echo "    ║      ╚═╝  ╚═╝╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝            ║"
    echo "    ║                                                           ║"
    echo "    ║       WireGuard + DNS Blocker + Unbound Stack            ║"
    echo "    ║                                                           ║"
    echo "    ╚═══════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

# Print step header with progress
step() {
    ((++CURRENT_STEP)) || true
    local description="$1"
    echo ""
    echo -e "${BOLD}${CYAN}[$CURRENT_STEP/$TOTAL_STEPS]${RESET} ${BOLD}$description${RESET}"
    echo -e "${DIM}$(printf '─%.0s' {1..60})${RESET}"
}

# Print success checkmark
success() {
    echo -e "  ${GREEN}✓${RESET} $1"
}

# Print info message
info() {
    echo -e "  ${CYAN}ℹ${RESET} $1"
}

# Print warning message
warn() {
    echo -e "  ${YELLOW}⚠${RESET} $1"
}

# Exit with error message and suggestions
error_exit() {
    echo -e "\n  ${RED}✗ Error: $1${RESET}" >&2
    if [[ -n "${2:-}" ]]; then
        echo -e "  ${DIM}Suggestion: $2${RESET}" >&2
    fi
    exit 1
}

# Spinner for long-running operations
spinner() {
    local pid=$1
    local message="${2:-Processing}"
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    tput civis  # Hide cursor
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${spin:i++%10:1}${RESET} %s..." "$message"
        sleep 0.1
    done
    tput cnorm  # Show cursor
    printf "\r  ${GREEN}✓${RESET} %s    \n" "$message"
}

# Run command with spinner
run_with_spinner() {
    local message="$1"
    shift
    
    # Run command in background
    "$@" > /dev/null 2>&1 &
    local pid=$!
    
    spinner "$pid" "$message"
    wait "$pid"
    return $?
}

# Print configuration summary
print_summary() {
    echo -e "\n${BOLD}Configuration Summary${RESET}"
    echo -e "${DIM}$(printf '─%.0s' {1..40})${RESET}"
    echo -e "  DNS Blocker:    ${GREEN}${WGEASY_DNS^}${RESET}"
    echo -e "  Docker Network: ${CYAN}$ADAKA_DEFAULT_NETWORK${RESET}"
    echo -e "  VPN Network:    ${CYAN}$WGEASY_DEFAULT_NETWORK${RESET}"
    echo -e "  Timezone:       ${CYAN}$ADAKA_DEFAULT_TZ${RESET}"
    echo -e "  Install Path:   ${CYAN}$ADAKA_DIR${RESET}"
    echo ""
}

# Print final success with service URLs
print_success() {
    local public_ip="$1"
    local dns_choice="$2"
    
    echo -e "${GREEN}${BOLD}✔ Setup Complete!${RESET}\n"

    echo -e "${BOLD}Service URLs:${RESET}"
    echo -e "${DIM}$(printf '─%.0s' {1..40})${RESET}"
    echo -e "  ${CYAN}WireGuard VPN${RESET}    http://${GREEN}$public_ip:51821${RESET}"
    echo -e "  ${CYAN}${dns_choice^} DNS${RESET}     http://${GREEN}$public_ip:8083/admin${RESET}"
    echo -e "  ${CYAN}Portainer${RESET}        http://${GREEN}$public_ip:9000${RESET}"
    echo ""
    echo -e "${BOLD}Quick Start:${RESET}"
    echo -e "${DIM}$(printf '─%.0s' {1..40})${RESET}"
    echo -e "  1. Open WireGuard admin at ${GREEN}http://$public_ip:51821${RESET}"
    echo -e "  2. Create a new VPN client"
    echo -e "  3. Scan QR code with WireGuard mobile app"
    echo ""
    
    if [[ "$dns_choice" == "adguard" ]]; then
        echo -e "${YELLOW}${BOLD} AdGuard Setup Required:${RESET}"
        echo -e "${DIM}$(printf '─%.0s' {1..40})${RESET}"
        echo -e "  1. Visit ${GREEN}http://$public_ip:3000${RESET} for initial setup"
        echo -e "  2. Set upstream DNS to: ${GREEN}${UNBOUND_IPV4_ADDRESS}:5335${RESET}"
        echo ""
    fi
    
    echo -e "${CYAN}${BOLD} Portainer:${RESET} Create admin account on first login"
    echo -e "${DIM}  Password: Use any secure password (not the one from -p flag)${RESET}"
    echo ""
}

# Legacy feedback function (for compatibility)
feedback() {
    info "$1"
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

# Detect package manager and OS
detect_os() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
    else
        error_exit "Unsupported package manager. Install Docker manually."
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
    if ! command -v docker &> /dev/null; then
        warn "Docker not found - installing"
        detect_os
        
        case "$PKG_MANAGER" in
            apt)
                info "Detected Debian/Ubuntu system"
                # Remove conflicting packages
                for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
                    sudo apt-get remove -y "$pkg" 2>/dev/null || true
                done

                # Set up Docker repository
                sudo apt-get update -qq
                sudo apt-get install -y -qq apt-transport-https ca-certificates curl software-properties-common
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

                # Install Docker components
                sudo apt-get update -qq
                sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
                success "Docker installed via apt"
                ;;
            dnf|yum)
                info "Detected Fedora/RHEL system"
                sudo "$PKG_MANAGER" install -y -q dnf-plugins-core
                sudo "$PKG_MANAGER" config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                sudo "$PKG_MANAGER" install -y -q docker-ce docker-ce-cli containerd.io docker-compose-plugin
                sudo systemctl start docker
                sudo systemctl enable docker
                success "Docker installed via $PKG_MANAGER"
                ;;
            pacman)
                info "Detected Arch Linux system"
                sudo pacman -Sy --noconfirm --quiet docker docker-compose
                sudo systemctl start docker
                sudo systemctl enable docker
                success "Docker installed via pacman"
                ;;
        esac
    fi
    
    # Verify docker compose is available
    if ! docker compose version &> /dev/null; then
        error_exit "Docker Compose plugin not available" "Install docker-compose-plugin package"
    fi
}

# Create directory structure with secure permissions
setup_directories() {
    local dirs=(
        "$ADAKA_DIR"
        "$WGEASY_DIR"
        "$PIHOLE_DIR/etc-pihole"
        "$ADGUARD_DIR/work"
        "$ADGUARD_DIR/conf"
        "$UNBOUND_DIR"
        "$PORTAINER_DIR/data"
    )
    
    local created=0
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || error_exit "Failed to create $dir" "Check permissions on parent directory"
            chmod 700 "$dir"
            ((created++))
        fi
    done
    
    if [[ $created -gt 0 ]]; then
        info "Created $created new directories"
    else
        info "All directories already exist"
    fi
}

# Generate bcrypt hash for WG-Easy password
generate_bcrypt_hash() {
    local password="$1"
    
    # Pull image if not present (avoid pulling every time)
    if ! docker image inspect python:3-alpine &> /dev/null; then
        info "Pulling Python image for password hashing"
        docker pull -q python:3-alpine || error_exit "Failed to pull python:3-alpine" "Check your internet connection"
    fi
    
    # Use environment variable to avoid command injection
    docker run --rm -e "HASH_PASSWORD=$password" python:3-alpine sh -c \
        'pip install -q bcrypt 2>/dev/null && python3 -c "import os,bcrypt; print(bcrypt.hashpw(os.environ[\"HASH_PASSWORD\"].encode(), bcrypt.gensalt()).decode())"' \
        | sed 's/\$/\$\$/g'  # Escape $ for docker-compose
}

# Retry wrapper for network operations
fetch_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries=3
    local attempt=0

    while (( attempt < max_retries )); do
        if curl -sSf --max-time 15 -o "$output" "$url" 2>/dev/null; then
            return 0
        fi
        ((attempt++))
        [[ $attempt -lt $max_retries ]] && sleep 2
    done

    error_exit "Failed to download from $url" "Check your internet connection"
}

# Configure Unbound services
configure_unbound() {
    # Download root hints
    info "Downloading DNS root hints"
    fetch_with_retry "https://www.internic.net/domain/named.root" "$UNBOUND_DIR/root.hints"
    success "Root hints downloaded"

    # Initialize DNSSEC trust anchor
    info "Initializing DNSSEC trust anchor"
    run_docker_with_retry "$UNBOUND_IMAGE" \
        "$UNBOUND_DIR:/opt/unbound/etc/unbound" \
        "unbound-anchor -a /opt/unbound/etc/unbound/root.key || true"
    success "DNSSEC trust anchor established"

    # Generate Unbound configuration
    info "Generating Unbound configuration"
    local unbound_template="$SCRIPT_DIR/.unbound.conf.template"
    if [[ ! -f "$unbound_template" ]]; then
        error_exit "Unbound template file missing" "Ensure $unbound_template exists"
    fi

    sed -e "s|{{ADAKA_NETWORK}}|$ADAKA_DEFAULT_NETWORK|g" \
        -e "s|{{UNBOUND_IPV4_ADDRESS}}|$UNBOUND_IPV4_ADDRESS|g" \
        "$unbound_template" > "$UNBOUND_DIR/unbound.conf" \
        || error_exit "Unbound configuration failed" "Check template syntax"
    
    success "Unbound configuration generated"
}

# Docker command retry logic
run_docker_with_retry() {
    local image="$1"
    local volume="$2"
    local command="$3"
    local max_retries=3
    local attempt=0

    # Pull image if needed
    if ! docker image inspect "$image" &> /dev/null; then
        info "Pulling image: $image"
        docker pull -q "$image" || error_exit "Failed to pull $image"
    fi

    while (( attempt < max_retries )); do
        if docker run --rm -v "$volume" "$image" sh -c "$command" 2>/dev/null; then
            return 0
        fi
        ((attempt++))
        [[ $attempt -lt $max_retries ]] && sleep 2
    done

    error_exit "Docker command failed after $max_retries attempts: $command"
}

# Generate Docker Compose configuration from template
generate_compose_config() {
    local template="$SCRIPT_DIR/.docker-compose.yml.template"
    local dns_template="$SCRIPT_DIR/.${WGEASY_DNS}.template"
    local dns_ip
    
    # Determine DNS service IP
    case "$WGEASY_DNS" in
        "pihole") dns_ip="$PIHOLE_IPV4_ADDRESS" ;;
        "adguard") dns_ip="$ADGUARD_IPV4_ADDRESS" ;;
        *) error_exit "Invalid DNS selection" ;;
    esac

    info "Processing Docker Compose templates"
    
    # Validate template files
    [[ -f "$template" ]] || error_exit "Main template missing" "Ensure $template exists"
    [[ -f "$dns_template" ]] || error_exit "DNS template missing" "Ensure $dns_template exists"

    # Insert DNS service section
    sed -e "/{{DNS_SECTION}}/r $dns_template" \
        -e "/{{DNS_SECTION}}/d" \
        "$template" > "$ADAKA_DIR/docker-compose.yml.tmp" \
        || error_exit "Template processing failed" "Check template syntax"

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
        -e "s|{{ADGUARD_DIR}}|$ADGUARD_DIR|g" \
        -e "s|{{ADGUARD_IPV4_ADDRESS}}|$ADGUARD_IPV4_ADDRESS|g" \
        -e "s|{{UNBOUND_IMAGE}}|$UNBOUND_IMAGE|g" \
        -e "s|{{UNBOUND_DIR}}|$UNBOUND_DIR|g" \
        -e "s|{{UNBOUND_IPV4_ADDRESS}}|$UNBOUND_IPV4_ADDRESS|g" \
        -e "s|{{PORTAINER_IMAGE}}|$PORTAINER_IMAGE|g" \
        -e "s|{{PORTAINER_DIR}}|$PORTAINER_DIR|g" \
        -e "s|{{PORTAINER_IPV4_ADDRESS}}|$PORTAINER_IPV4_ADDRESS|g" \
        "$ADAKA_DIR/docker-compose.yml.tmp" \
        || error_exit "Variable substitution failed" "Check template syntax"

    # Finalize configuration
    mv "$ADAKA_DIR/docker-compose.yml.tmp" "$ADAKA_DIR/docker-compose.yml" \
        || error_exit "Final compose file move failed"
    rm -f "$ADAKA_DIR/docker-compose.yml.tmp.bak"
    
    # Validate generated docker-compose.yml
    info "Validating Docker Compose configuration"
    if ! docker compose -f "$ADAKA_DIR/docker-compose.yml" config --quiet 2>/dev/null; then
        error_exit "Generated docker-compose.yml is invalid" "Check template substitutions"
    fi
    success "Docker Compose configuration validated"
}

# =============================================================================
# Main Execution Flow
# =============================================================================

# Parse command-line options
while getopts 'p:n:h' opt; do
    case "$opt" in
        p) ADAKA_PASSWORD="$OPTARG" ;;
        n) WGEASY_DNS="$OPTARG" ;;
        h) 
            echo "Usage: $0 -p <password> [-n pihole|adguard]"
            echo ""
            echo "Options:"
            echo "  -p <password>    Password for WireGuard and Pi-hole admin (required)"
            echo "  -n <dns>         DNS blocker: 'pihole' (default) or 'adguard'"
            echo "  -h               Show this help message"
            exit 0
            ;;
        *) error_exit "Usage: $0 -p password -n [pihole|adguard]" "Run '$0 -h' for help" ;;
    esac
done
shift "$((OPTIND-1))"

# Validate mandatory parameters
[[ -z "${ADAKA_PASSWORD:-}" ]] && error_exit "Password required (-p)" "Example: $0 -p 'MySecurePassword123'"
[[ "$WGEASY_DNS" =~ ^(pihole|adguard)$ ]] || error_exit "Invalid DNS option: $WGEASY_DNS" "Use 'pihole' or 'adguard'"

# Show welcome banner
print_banner

# Validate configured subnets
validate_subnet "$ADAKA_DEFAULT_NETWORK"
validate_subnet "$WGEASY_DEFAULT_NETWORK"

# Show configuration summary
print_summary

# ─────────────────────────────────────────────────────────────────────────────
step "Detecting Network Configuration"
# ─────────────────────────────────────────────────────────────────────────────

info "Fetching public IP address"
ADAKA_PUBLIC_IP=$(curl -4 -s --max-time 10 --retry 3 ifconfig.me)
[[ -z "$ADAKA_PUBLIC_IP" ]] && error_exit "Failed to get public IP" "Check your internet connection"
success "Public IP: $ADAKA_PUBLIC_IP"

WGEASY_NETWORK=$(convert_wg_network "$WGEASY_DEFAULT_NETWORK") || exit 1
success "WireGuard network configured"

# ─────────────────────────────────────────────────────────────────────────────
step "Checking Prerequisites"
# ─────────────────────────────────────────────────────────────────────────────

install_dependencies
success "Docker is available"
success "Docker Compose is available"

# ─────────────────────────────────────────────────────────────────────────────
step "Creating Directory Structure"
# ─────────────────────────────────────────────────────────────────────────────

setup_directories
success "All directories created with secure permissions"

# ─────────────────────────────────────────────────────────────────────────────
step "Configuring Unbound DNS Resolver"
# ─────────────────────────────────────────────────────────────────────────────

configure_unbound
success "Unbound configured with DNSSEC enabled"

# ─────────────────────────────────────────────────────────────────────────────
step "Generating Service Credentials"
# ─────────────────────────────────────────────────────────────────────────────

info "Hashing password for WireGuard"
WGEASY_PASSWORD=$(generate_bcrypt_hash "$ADAKA_PASSWORD")
success "WireGuard password hash generated"

# Escape password for safe YAML embedding (handles all special chars)
escape_for_yaml() {
    local input="$1"
    printf '%s' "$input" | sed -e 's/\\/\\\\/g' -e 's/|/\\|/g' -e 's/&/\\\&/g' -e 's/#/\\#/g' -e "s/'/\\'/g" -e 's/"/\\"/g'
}

PIHOLE_WEBPASSWORD=$(escape_for_yaml "$ADAKA_PASSWORD")
success "Pi-hole credentials configured"

# ─────────────────────────────────────────────────────────────────────────────
step "Building Docker Configuration"
# ─────────────────────────────────────────────────────────────────────────────

generate_compose_config
success "Docker Compose configuration generated"
success "Configuration validated successfully"

# ─────────────────────────────────────────────────────────────────────────────
step "Stopping Existing Services"
# ─────────────────────────────────────────────────────────────────────────────

info "Cleaning up any existing containers"
docker compose -f "$ADAKA_DIR/docker-compose.yml" -p adaka down --remove-orphans 2>/dev/null || true
success "Environment cleaned"

# ─────────────────────────────────────────────────────────────────────────────
step "Launching Services"
# ─────────────────────────────────────────────────────────────────────────────

info "Starting containers (this may take a few minutes on first run)"
echo ""

# Show container pull/start progress
docker compose -f "$ADAKA_DIR/docker-compose.yml" -p adaka up -d --force-recreate \
    || error_exit "Failed to start services" "Check 'docker compose logs' for details"

echo ""
success "All containers started successfully"

# Wait for services to be healthy
info "Waiting for services to initialize"
sleep 5

# Check container status
RUNNING_CONTAINERS=$(docker compose -f "$ADAKA_DIR/docker-compose.yml" -p adaka ps --format "{{.Name}}" 2>/dev/null | wc -l)
success "$RUNNING_CONTAINERS containers running"

# Show final success message
print_success "$ADAKA_PUBLIC_IP" "$WGEASY_DNS"