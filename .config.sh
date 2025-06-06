#!/bin/bash
# Docker Images & Versions
WGEASY_IMAGE="ghcr.io/wg-easy/wg-easy:latest"
PIHOLE_IMAGE="pihole/pihole:latest"
UNBOUND_IMAGE="mvance/unbound:latest"
PORTAINER_IMAGE="portainer/portainer-ce:latest"
ADGUARD_IMAGE="adguard/adguardhome:latest"



# Directory paths and default settings
ADAKA_DIR="$HOME/.adaka"
WGEASY_DIR="$ADAKA_DIR/.wg-easy"
PIHOLE_DIR="$ADAKA_DIR/.pihole"
ADGUARD_DIR="$ADAKA_DIR/.adguard"
UNBOUND_DIR="$ADAKA_DIR/.unbound"
PORTAINER_DIR="$ADAKA_DIR/.portainer"
ADAKA_DEFAULT_NETWORK="10.8.1.0/24"
WGEASY_DEFAULT_NETWORK="192.168.100.0/24"
WGEASY_DEFAULT_DNS="pihole"
ADAKA_DEFAULT_TZ="$(timedatectl show --property=Timezone | cut -d= -f2)"
WGEASY_IPV4_ADDRESS="10.8.1.2"
PIHOLE_IPV4_ADDRESS="10.8.1.3"
ADGUARD_IPV4_ADDRESS="10.8.1.3"
UNBOUND_IPV4_ADDRESS="10.8.1.5"
PORTAINER_IPV4_ADDRESS="10.8.1.6"


#user supplied configuration parameter
# PIHOLE_PASSWORD=
# WGEASY_PASSWORD=
# PORTAINER_PASSWORD=
# ADAKA_NETWORK=
# WGEASY_NETWORK=