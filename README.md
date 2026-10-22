# Adaka

A self-hosted VPN + DNS privacy stack using Docker. Combines WireGuard VPN with your choice of DNS blocker (Pi-hole or AdGuard Home) and Unbound recursive DNS resolver with DNSSEC.

```
ADAKA
```

## Features

- **WireGuard VPN** - Fast, modern VPN with easy client management via web UI
- **DNS Blocking** - Choose between Pi-hole or AdGuard Home for ad/tracker blocking
- **DNSSEC** - Cryptographically verified DNS responses via Unbound
- **Arcane** - Docker management dashboard (containers, images, logs, updates)
- **SearXNG** - Private metasearch engine, queried from your server instead of your devices
- **VPN-only admin** - Every web UI except the WireGuard admin is reachable only over the VPN
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
- Open ports: `51820/udp` (WireGuard), `51821/tcp` (WireGuard admin UI). Nothing else is published.

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
        │  │ WireGuard │  │  Arcane   │            │
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
| WireGuard | 10.8.1.2 | 51820/udp | VPN server |
| Pi-hole | 10.8.1.3 | - | DNS blocker (option 1) |
| AdGuard | 10.8.1.4 | - | DNS blocker (option 2) |
| Unbound | 10.8.1.5 | - | DNSSEC recursive resolver |
| Arcane | 10.8.1.6 | - | Docker management |
| Caddy | 10.8.1.7 | 51821/tcp | TLS for the WireGuard admin UI; proxy for VPN-only services |
| SearXNG | 10.8.1.8 | - | Private metasearch |

## Accessing Services

Only the WireGuard admin UI is public. Everything else is served by Caddy at
`<service>.adaka.internal` and is reachable **only while connected to the VPN**:
the VPN's DNS (Pi-hole) resolves `*.adaka.internal` to Caddy, and Caddy's
internal port is not published on the host.

| Service | URL | Access |
|---------|-----|--------|
| WireGuard VPN | `https://<YOUR_IP>:51821` (self-signed cert) | Public |
| Pi-hole/AdGuard | `http://dns.adaka.internal/admin` | VPN only |
| SearXNG | `http://search.adaka.internal` | VPN only |
| Arcane | `http://arcane.adaka.internal` | VPN only |

These URLs are plain HTTP, but the traffic travels inside the encrypted
WireGuard tunnel. To make SearXNG your browser's search engine, add
`http://search.adaka.internal/search?q=%s` as a custom search engine.

To add another private service, attach it to `adaka_network` without
publishing ports and add an `http://<name>.adaka.internal` block to the
Caddyfile. No DNS change is needed.

### First-time Setup

1. **WireGuard**: Log in with your password, create a new client, scan QR code with WireGuard app
2. **Pi-hole**: Log in with your password at `/admin`
3. **AdGuard**: Connect to the VPN, complete the setup wizard at `http://10.8.1.4:3000`, set upstream DNS to `10.8.1.5:5335`, and add a DNS rewrite `*.adaka.internal` → `10.8.1.7`
4. **Arcane**: Log in as `arcane` / `arcane-admin`; you must set a new password on first login

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
├── arcane/           # Arcane data and encryption.key (keep it: it decrypts stored secrets)
├── caddy/            # Caddyfile and TLS state
├── searxng/          # SearXNG settings.yml (rendered from .searxng-settings.yml.template), secret.key, cache
└── docker-compose.yml
```

## Security Features

- **DNSSEC validation** with automatic trust anchor updates
- **Hardened Unbound** configuration (hidden identity, rate limiting, cache poisoning protection)
- **bcrypt password hashing** for WireGuard admin
- **Secure YAML escaping** prevents injection attacks
- **Access control** - DNS resolver only accessible from internal networks
- **Minimal attack surface** - Only WireGuard (51820/udp) and its TLS admin UI (51821/tcp) are published

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
- WireGuard admin: verify your firewall allows `51821/tcp`
- `*.adaka.internal` services: connect to the VPN first, and check that your
  device uses the VPN's DNS (`nslookup search.adaka.internal` should return `10.8.1.7`)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Made with ❤️ for privacy enthusiasts**
