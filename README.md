# Proton VPN WireGuard Docker Image

Containerized WireGuard client for Proton VPN using wg-quick and your Proton-provided WireGuard configuration files. No ProtonVPN CLI, no keyring prompts — designed for headless use.  
Important: This project is not affiliated with Proton AG.

# Docker Desktop on Macos
There is an issue with running this script after changing the configuration file. Docker desktop requries to be rebooted before changing the config file. 

---

## What this provides

- WireGuard-only VPN client inside a container
- Picks a .conf by explicit name, server code, or country code
- Optional IPv6 routing addition (adds ::/0 to AllowedIPs)
- Optional removal of DNS= lines to avoid resolver dependencies in containers
- Clean bring-up/down via wg-quick (interface wg0)
- **SOCKS5 proxy server inside the container for other services to proxy traffic through the WireGuard tunnel**

---

## Repository contents

- `dockerfile` — Dockerfile for the image
- `start_wireguard.sh` — Entrypoint script, now runs WireGuard and a SOCKS5 proxy
- `.env` — Example environment defaults

---

## Requirements

- Linux host with Docker and /dev/net/tun
- Container flags:
  - `--cap-add=NET_ADMIN`
  - `--device /dev/net/tun`
- Proton VPN account and WireGuard configuration files downloaded from your Proton dashboard

Notes:  
- Proton recommends WireGuard .conf filenames under 15 characters.  
- Do not commit your .conf files; they contain keys.

---

## Get Proton WireGuard configs

1. Sign in to your Proton account and go to Downloads → WireGuard configuration  
2. Generate and download .conf files for servers/countries you want to use  
3. Keep filenames under 15 characters (rename if necessary)  
4. Place them in a directory you will mount into the container (e.g., `/path/to/wg-configs`)  

IPv6 note:  
- Proton’s default WireGuard configs are IPv4-only. This image can add ::/0 automatically if you set `PVPN_IPV6=on`.

---


## Quick start (docker run)

Mount your configs and choose by country:

```
docker run --rm -it \                           
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  -p 1080:1080/tcp \
  -v /Users/dan/Documents/wireguard-pvpn-conf:/wireguard:ro \
  -e PVPN_COUNTRY=US \
  -e PVPN_WG_STRATEGY=first \
  -e PVPN_IPV6=off \
  -e PVPN_WG_DNS=on \
  -e PROXY_PORT=1080 \
  ghcr.io/cryptshoe/docker-pvpn:latest
  ```

### Environment variables

- `PVPN_WG_DIR`: directory of .conf files (default `/wireguard`)  
- `PVPN_WG_NAME`: explicit config filename or basename (preferred exact match)  
- `PVPN_SERVER`: server basename/prefix to match (e.g., `swiss1-CH-5`)  
- `PVPN_COUNTRY`: country code to select by (e.g., `CH`, `US`, `DE`)  
- `PVPN_WG_STRATEGY`: `first` (default) or `random` when multiple match  
- `PVPN_IPV6`: `on` to append `::/0` to AllowedIPs if missing (default `off`)  
- `PVPN_WG_DNS`: `on` to keep DNS= lines, `off` to strip them (default `on`)  
- `PROXY_PORT`: port number of the SOCKS5 proxy exposed by the container (default `1080`)  
- `TZ`: optional timezone for logs  

DNS behavior:  
- If your config includes `DNS=`, keeping it on may require resolvconf/systemd-resolved in the container. If you don’t want DNS managed inside the container, set `PVPN_WG_DNS=off`.

---

## Using the SOCKS5 proxy

- The container runs a SOCKS5 proxy server listening on `PROXY_PORT` (default `1080`).  
- Other services can connect to this port to proxy their traffic through the WireGuard tunnel.  
- SOCKS5 supports HTTP, HTTPS, and other TCP protocols (as well as some UDP).  
- Configure client applications to use `socks5://<container-ip-or-host>:${PROXY_PORT}`.

---

## Verifying the connection

Inside the container:
```
wg show
```
Alternatively:
```
ip addr show wg0
```
External check: use a web IP checker from an app sharing the `pvpn` container’s network or using the SOCKS5 proxy.

---

## Using as a gateway for another container

Run the VPN container, then attach your app to its network namespace so all traffic egresses via WireGuard:
```
docker run -d --name pvpn --cap-add=NET_ADMIN --device /dev/net/tun \
  -v /path/to/wg-configs:/wireguard:ro \
  -e PVPN_COUNTRY=CH docker-pvpn
```
```
docker run -d --network container:pvpn your-app-image
```
Notes on kill switch behavior:  
- This image does not alter host or container-wide iptables beyond wg-quick defaults. For stricter isolation, keep your apps using `--network container:pvpn` or implement policy routing/firewall rules on the host as needed.

---

## Troubleshooting

- `/dev/net/tun` missing:  
  Ensure the device is present on the host and passed with `--device /dev/net/tun` and `--cap-add=NET_ADMIN`

- No configs found:  
  Confirm you mounted the directory with `.conf` files to `/wireguard` or set `PVPN_WG_DIR`

- DNS resolution issues:  
  Either enable DNS= handling (`PVPN_WG_DNS=on`) and ensure resolvconf/systemd-resolved works in the image, or disable it (`PVPN_WG_DNS=off`)

- IPv6 not routed:  
  Set `PVPN_IPV6=on` to add `::/0` if your environment supports IPv6 over the tunnel

- Multiple matching configs:  
  Use `PVPN_WG_STRATEGY=random` (requires `shuf`) or refine your selection with `PVPN_WG_NAME` or `PVPN_SERVER`

---

## CI/CD

- See `.github/workflows/docker-pvpn.yml` for multi-arch builds and GHCR publishing

---

## License

Add your chosen license here.

---

## Disclaimer

Use responsibly and in accordance with local laws and Proton VPN’s terms of service.
