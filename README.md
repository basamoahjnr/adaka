# Adaka Setup Script

This script automates the installation and configuration of Pi-hole, WireGuard, and Unbound using Docker. It streamlines the setup process by managing necessary configurations and dependencies.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Options](#options)
- [Configuration](#configuration)
- [Installation Instructions](#installation-instructions)
- [License](#license)

## Prerequisites

- A Unix-based system (Linux, macOS)
- [Docker](https://docs.docker.com/get-docker/) installed
- [Docker Compose](https://docs.docker.com/compose/install/) installed

## Usage

1. Clone or download the script to your local machine.
2. Open a terminal and navigate to the script's directory.
3. Run the script using the following command:

   ```bash
   ./adaka.sh -p <password> [-s <subnet>] [-u <wg-easy subnet>] [-t <timezone>]
   ```

   Replace `<password>`, `<subnet>`, `<wg-easy subnet>`, and `<timezone>` with your desired values.

## Options

- `-p <password>`: Required. The password for the wg-easy and Pi-hole web interfaces.
- `-s <subnet>`: Optional. The subnet for the Docker network (default: `10.8.1.0/24`).
- `-u <wg-easy subnet>`: Optional. The subnet for wg-easy clients (default: `192.168.100.x`).
- `-t <timezone>`: Optional. The timezone setting for Pi-hole (default is retrieved from the system).

## Configuration

The script creates the following directories:

- `~/.wirehole/.wg-easy`
- `~/.wirehole/.pihole`
- `~/.wirehole/.unbound`

Additionally, it generates:

- Docker Compose configuration file (`docker-compose.yml`)
- Unbound configuration file (`unbound.conf`)
- Root hints for Unbound
- DNSSEC root trust anchor


## Known Bug
1. FIXED: Passwords that have special characters dont work when passed as -p option using the script 
2. FIXED: Port 8083 for external access to pihole dont work, will be fixed soon

## Installation Instructions

1. Make the script executable:

   ```bash
   chmod +x adaka.sh
   ```

2. Execute the script with your desired options.

   ```bash
   ./adaka.sh -p mysecurepassword
   ```

3. Follow the prompts and wait for the setup to complete.

## Accessing Services

- **Pi-hole Web Interface**: 
  - URL: `http://<YOUR_PUBLIC_IP>:8083/admin` 
  - OR: `http://10.8.0.3:80/admin`

- **wg-easy Web Interface**: 
  - URL: `http://<YOUR_PUBLIC_IP>:51821` 
  - OR: `http://10.8.0.2:51821`



## License

This project is licensed under the MIT License

---
