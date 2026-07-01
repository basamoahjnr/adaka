# =============================================================================
# Adaka Configuration
# =============================================================================

# Docker Images (using latest tags - consider pinning for production)
WGEASY_IMAGE="ghcr.io/wg-easy/wg-easy:latest"
PIHOLE_IMAGE="pihole/pihole:latest"
UNBOUND_IMAGE="mvance/unbound:1.22.0"
PORTAINER_IMAGE="portainer/portainer-ce:latest"
ADGUARD_IMAGE="adguard/adguardhome:latest"

# Directory paths
ADAKA_DIR="$HOME/.adaka"
WGEASY_DIR="$ADAKA_DIR/wg-easy"
PIHOLE_DIR="$ADAKA_DIR/pihole"
ADGUARD_DIR="$ADAKA_DIR/adguard"
UNBOUND_DIR="$ADAKA_DIR/unbound"
PORTAINER_DIR="$ADAKA_DIR/portainer"

# Network configuration
# Note: Ensure these don't conflict with your local network
ADAKA_DEFAULT_NETWORK="10.8.1.0/24"
WGEASY_DEFAULT_NETWORK="192.168.100.0/24"
WGEASY_DEFAULT_DNS="pihole"

# fail2ban SSH jail settings (blocks brute-force/bot login attempts)
FAIL2BAN_BANTIME="1h"
FAIL2BAN_FINDTIME="10m"
FAIL2BAN_MAXRETRY="5"

# Timezone detection with fallback
if command -v timedatectl &> /dev/null; then
    ADAKA_DEFAULT_TZ="$(timedatectl show --property=Timezone 2>/dev/null | cut -d= -f2)"
fi
ADAKA_DEFAULT_TZ="${ADAKA_DEFAULT_TZ:-UTC}"

# Container IP addresses (sequential within ADAKA_DEFAULT_NETWORK)
WGEASY_IPV4_ADDRESS="10.8.1.2"
PIHOLE_IPV4_ADDRESS="10.8.1.3"
ADGUARD_IPV4_ADDRESS="10.8.1.4"
UNBOUND_IPV4_ADDRESS="10.8.1.5"
PORTAINER_IPV4_ADDRESS="10.8.1.6"

# =============================================================================
# Note: The following are set via CLI arguments and cannot be configured here:
#   -p <password>        : Shared password for all web interfaces
#   -n <pihole|adguard>  : DNS blocker selection (default: pihole)
# =============================================================================