#!/bin/bash

# Docker Images & Versions
WGEASY_IMAGE="ghcr.io/wg-easy/wg-easy:latest"
PIHOLE_IMAGE="pihole/pihole:latest"
UNBOUND_IMAGE="mvance/unbound:latest"

# Directory paths and default settings
ADAKA_DIR="$HOME/.adaka"
WG_DIR="$ADAKA_DIR/.wg-easy"
PIHOLE_DIR="$ADAKA_DIR/.pihole"
UNBOUND_DIR="$ADAKA_DIR/.unbound"
ADAKA_DEFAULT_NETWORK="10.8.1.0/24"
WGEASY_DEFAULT_NETWORK="192.168.100.0/24"
ADAKA_DEFAULT_TZ=$(cat /etc/timezone)
# PIHOLE_SECONDARY_DNS_SERVER="8.8.8.8"