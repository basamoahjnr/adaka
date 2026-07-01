# Adaka

A self-hosted VPN + DNS privacy stack using Docker. Combines WireGuard VPN with your choice of DNS blocker (Pi-hole or AdGuard Home) and Unbound recursive DNS resolver with DNSSEC.

```
ADAKA
```

## Features

- **WireGuard VPN** - Fast, modern VPN with easy client management via web UI
- **DNS Blocking** - Choose between Pi-hole or AdGuard Home for ad/tracker blocking
- **DNSSEC** - Cryptographically verified DNS responses via Unbound
- **Portainer** - Docker management dashboard
- **One-command setup** - Automated installation with progress feedback
- **Cross-distro support** - Works on Debian/Ubuntu, Fedora/RHEL, Arch Linux

## Quick Start

```bash
# Clone the repository
git clone https://github.com/yourusername/adaka.git
cd adaka

# Make executable
chmod +x adaka.sh

# Run with Pi-hole (default)
./adaka.sh -p 'YourSecurePassword'

# Or run with AdGuard Home
./adaka.sh -p 'YourSecurePassword' -n adguard
```

## Prerequisites

- Linux server (Debian, Ubuntu, Fedora, RHEL, Arch, etc.)
- Docker and Docker Compose (auto-installed if missing)
- Root/sudo access
- Open ports: `51820/udp` (WireGuard), `51821`, `8083`, `9000` (web UIs)

## Usage

```bash
./adaka.sh -p <password> [-n pihole|adguard]
```

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `-p <password>` | Password for WireGuard and DNS blocker admin | **Required** |
| `-n <dns>` | DNS blocker: `pihole` or `adguard` | `pihole` |
| `-h` | Show help message | - |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Internet                                │
└─────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │   Your Server     │
                    │   (Public IP)     │
                    └─────────┬─────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │              Docker Network               │
        │            (10.8.1.0/24)                  │
        │                                           │
        │  ┌───────────┐  ┌───────────┐            │
        │  │ WireGuard │  │ Portainer │            │
        │  │  :51820   │  │   :9000   │            │
        │  │  :51821   │  │           │            │
        │  └─────┬─────┘  └───────────┘            │
        │        │                                  │
        │        ▼                                  │
        │  ┌───────────┐                           │
        │  │  Pi-hole  │  (or AdGuard Home)        │
        │  │   :8083   │                           │
        │  └─────┬─────┘                           │
        │        │                                  │
        │        ▼                                  │
        │  ┌───────────┐                           │
        │  │  Unbound  │  DNSSEC Resolver          │
        │  │   :5335   │                           │
        │  └─────┬─────┘                           │
        │        │                                  │
        └────────┼──────────────────────────────────┘
                 │
                 ▼
         Root DNS Servers
```

## Services

| Service | Internal IP | External Port | Purpose |
|---------|-------------|---------------|---------|
| WireGuard | 10.8.1.2 | 51820/udp, 51821 | VPN server + web UI |
| Pi-hole | 10.8.1.3 | 8083 | DNS blocker (option 1) |
| AdGuard | 10.8.1.4 | 8083, 3000* | DNS blocker (option 2) |
| Unbound | 10.8.1.5 | - | DNSSEC recursive resolver |
| Portainer | 10.8.1.6 | 9000 | Docker management |

*Port 3000 is used for AdGuard initial setup only

## Accessing Services

After installation, access your services at:

| Service | URL |
|---------|-----|
| WireGuard VPN | `http://<YOUR_IP>:51821` |
| Pi-hole/AdGuard | `http://<YOUR_IP>:8083/admin` |
| Portainer | `http://<YOUR_IP>:9000` |

### First-time Setup

1. **WireGuard**: Log in with your password, create a new client, scan QR code with WireGuard app
2. **Pi-hole**: Log in with your password at `/admin`
3. **AdGuard**: Complete setup wizard at port 3000, set upstream DNS to `10.8.1.5:5335`
4. **Portainer**: Create admin account on first visit (use any password)

## Configuration

Configuration is stored in `.config.sh`. Key settings:

```bash
# Networks
ADAKA_DEFAULT_NETWORK="10.8.1.0/24"      # Docker network
WGEASY_DEFAULT_NETWORK="192.168.100.0/24" # VPN client network

# Data directories
ADAKA_DIR="$HOME/.adaka"                  # All service data
```

### Directory Structure

```
~/.adaka/
├── wg-easy/          # WireGuard configuration
├── pihole/           # Pi-hole data (or adguard/)
├── unbound/          # Unbound config & DNSSEC keys
├── portainer/        # Portainer data
└── docker-compose.yml
```

## Security Features

- **DNSSEC validation** with automatic trust anchor updates
- **Hardened Unbound** configuration (hidden identity, rate limiting, cache poisoning protection)
- **bcrypt password hashing** for WireGuard admin
- **Secure YAML escaping** prevents injection attacks
- **Access control** - DNS resolver only accessible from internal networks

## Managing Services

```bash
# View logs
docker compose -f ~/.adaka/docker-compose.yml logs -f

# Restart all services
docker compose -f ~/.adaka/docker-compose.yml restart

# Stop all services
docker compose -f ~/.adaka/docker-compose.yml down

# Update containers
docker compose -f ~/.adaka/docker-compose.yml pull
docker compose -f ~/.adaka/docker-compose.yml up -d
```

## Troubleshooting

### Can't connect to VPN
- Ensure port `51820/udp` is open in your firewall
- Check WireGuard logs: `docker logs adaka-wg-easy-1`

### DNS not working
- Verify Unbound is running: `docker logs adaka-unbound-1`
- Test DNS resolution: `docker exec adaka-unbound-1 drill google.com @127.0.0.1 -p 5335`

### Web UI not accessible
- Check if containers are running: `docker ps`
- Verify firewall allows ports 51821, 8083, 9000

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Made with ❤️ for privacy enthusiasts**
