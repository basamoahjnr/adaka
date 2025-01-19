#!/bin/bash
# Docker Images & Versions
WGEASY_IMAGE="ghcr.io/wg-easy/wg-easy:latest"
PIHOLE_IMAGE="pihole/pihole:latest"
UNBOUND_IMAGE="mvance/unbound:latest"
PORTAINER_IMAGE="portainer/portainer-ce:latest"



# Directory paths and default settings
ADAKA_DIR="$HOME/.adaka"
WGEASY_DIR="$ADAKA_DIR/.wg-easy"
PIHOLE_DIR="$ADAKA_DIR/.pihole"
UNBOUND_DIR="$ADAKA_DIR/.unbound"
PORTAINER_DIR="$ADAKA_DIR/.portainer"
ADAKA_DEFAULT_NETWORK="10.8.1.0/24"
WGEASY_DEFAULT_NETWORK="192.168.100.0/24"
ADAKA_DEFAULT_TZ="$(cat /etc/timezone)"


#user supplied configuration parameter
# PIHOLE_PASSWORD=
# WGEASY_PASSWORD=
# PORTAINER_PASSWORD=
# ADAKA_NETWORK=
# WGEASY_NETWORK=