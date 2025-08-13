# ProtonVPN Docker Image

Containerized ProtonVPN CLI based on Ubuntu. This image installs ProtonVPN CLI and runs an entrypoint script to authenticate and connect.

Important: This project is not affiliated with Proton AG.

## Contents

- dockerfile — Dockerfile that builds the image
- start_protonvpn.sh — Entrypoint script invoked by the container

## Requirements

- Linux host with Docker and `/dev/net/tun` available
- Container must be granted:
  - `--cap-add=NET_ADMIN`
  - `--device /dev/net/tun`
- Proton VPN account credentials

> Note: Exposing port 1194 is typically unnecessary for outbound VPN client usage.

## Build

Local build:
- docker build -t docker-pvpn -f docker-pvpn/dockerfile docker-pvpn

GitHub Actions build (optional):
- A workflow example exists at `.github/workflows/docker-pvpn.yml` that builds on pushes/PRs and pushes to GHCR on non-PR events.
- Resulting image: `ghcr.io/<owner>/docker-pvpn:latest` (plus branch and SHA tags)

## Run

Interactive (manual login):
- docker run --rm -it --cap-add=NET_ADMIN --device /dev/net/tun --entrypoint bash docker-pvpn
- Inside container:
  - protonvpn-cli login
  - protonvpn-cli c -f
  - protonvpn-cli status

Headless with env vars:
- docker run -d --name pvpn --cap-add=NET_ADMIN --device /dev/net/tun --restart unless-stopped \
    -e PVPN_USERNAME=you@example.com -e PVPN_PASSWORD='your-password' docker-pvpn

Use as a VPN gateway for another container:
- docker run -d --name pvpn --cap-add=NET_ADMIN --device /dev/net/tun docker-pvpn
- docker run -d --network container:pvpn your-app-image

## Environment variables

- `PVPN_USERNAME` — Proton VPN username
- `PVPN_PASSWORD` — Proton VPN password
- `PVPN_SERVER` — Specific server name (e.g., `US-CA#1`) if preferred
- `PVPN_COUNTRY` — Country code (e.g., `US`, `DE`) as fallback
- `PVPN_PROTOCOL` — `udp` or `tcp` (default `udp`)
- `PVPN_KILLSWITCH` — `on` or `off` (default `on`)
- `PVPN_DNS` — `on` or `off` (default `on`)

## Troubleshooting

- Dependencies:
  - If you see OpenVPN/DNS errors, add packages in the Dockerfile:
    - `openvpn resolvconf wireguard-tools iproute2`
- TUN device:
  - Ensure host has `/dev/net/tun` and container has `--device /dev/net/tun` and `--cap-add=NET_ADMIN`
- Check status:
  - `protonvpn-cli status` inside the container

## CI/CD

- See `.github/workflows/docker-pvpn.yml` for a GH Actions workflow that:
  - Builds multi-arch images (linux/amd64, linux/arm64)
  - Pushes to GHCR with branch/SHA tags and `latest` on default branch

## License

Add your chosen license here.

## Disclaimer

Use responsibly and in accordance with local laws and Proton VPN’s terms of service.
