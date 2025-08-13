# Proton VPN WireGuard Docker Image

Containerized WireGuard client for Proton VPN configs based on Ubuntu. This image uses wg-quick to bring up a tunnel from your Proton-provided WireGuard configuration files.

Important: This project is not affiliated with Proton AG.

## Contents

- dockerfile — Dockerfile that builds the image
- start_wireguard.sh — Entrypoint script invoked by the container

## Requirements

- Linux host with Docker and `/dev/net/tun` available
- Container must be granted:
  - `--cap-add=NET_ADMIN`
  - `--device /dev/net/tun`
- Proton VPN account to download WireGuard configuration files from your dashboard
- WireGuard configuration files mounted into the container (default path `/wireguard`)

> Proton advises keeping WireGuard `.conf` filenames under 15 characters.

## Build

Local build:
- docker build -t docker-pvpn -f dockerfile .

GitHub Actions build (optional):
- A workflow example exists at `.github/workflows/docker-pvpn.yml` that builds on pushes/PRs and pushes to GHCR on non-PR events.
- Resulting image: `ghcr.io/<owner>/docker-pvpn:latest` (plus branch and SHA tags)

## Run

Mount your Proton WireGuard config files into the container at `/wireguard` (or set `PVPN_WG_DIR` to another path). The entrypoint will select a config based on environment variables and bring up the interface `wg0` using `wg-quick`.

Example: choose by country code (first match):

```
docker run --rm -it \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -v /path/to/your/wireguard/configs:/wireguard:ro \
  -e PVPN_COUNTRY='CH' \
  -e PVPN_WG_STRATEGY='first' \
  -e PVPN_IPV6='on' \
  -e PVPN_WG_DNS='off' \
  docker-pvpn
```

Other selection methods:
- `PVPN_WG_NAME` — exact file name (with or without `.conf`), e.g., `swiss1-CH-5.conf` or `swiss1-CH-5`
- `PVPN_SERVER` — basename/prefix match, e.g., `swiss1-CH-5`
- `PVPN_COUNTRY` — country code (e.g., `CH`, `US`, `DE`); strategy can be `first` (default) or `random`
- If only one `.conf` exists in the directory, it will be selected automatically.

## Environment variables

- `PVPN_WG_DIR` — directory containing `.conf` files (default `/wireguard`)
- `PVPN_WG_NAME` — explicit config filename or basename
- `PVPN_SERVER` — server basename/prefix to match
- `PVPN_COUNTRY` — country code for selection
- `PVPN_WG_STRATEGY` — `first` (default) or `random` to choose among matches
- `PVPN_IPV6` — `on` to append `::/0` to AllowedIPs if missing (default `off`)
- `PVPN_WG_DNS` — `on` to keep `DNS=` lines, `off` to remove them (default `on`)

## Verifying connection

- Inside the container: `wg show` (or `ip addr show wg0` if `wg` is not available)
- From outside: check your public IP using a web service while routing through this container

## Using as a gateway for another container

Run this container and then attach another container to its network namespace:

```
docker run -d --name pvpn --cap-add=NET_ADMIN --device /dev/net/tun \
  -v /path/to/configs:/wireguard:ro \
  -e PVPN_COUNTRY=CH docker-pvpn

docker run -d --network container:pvpn your-app-image
```

## Troubleshooting

- TUN device:
  - Ensure host has `/dev/net/tun` and container has `--device /dev/net/tun` and `--cap-add=NET_ADMIN`
- DNS inside container:
  - If your config includes `DNS=` and you want it applied, ensure `resolvconf` or systemd-resolved integration is available; otherwise set `PVPN_WG_DNS=off` to skip DNS changes inside the container
- IPv6 routing:
  - Set `PVPN_IPV6=on` to add `::/0` to AllowedIPs if your host supports IPv6 through the tunnel
- Multiple matching configs:
  - Use `PVPN_WG_STRATEGY=random` to vary the selection if `shuf` is available

## CI/CD

- See `.github/workflows/docker-pvpn.yml` for a GH Actions workflow that builds multi-arch images and publishes to GHCR.

## License

Add your chosen license here.

## Disclaimer

Use responsibly and in accordance with local laws and Proton VPN’s terms of service.
