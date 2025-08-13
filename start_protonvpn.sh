#!/usr/bin/env bash
set -euo pipefail

# ProtonVPN Docker Entrypoint
# - Optionally logs in using PVPN_USERNAME/PVPN_PASSWORD
# - Applies configuration (protocol, killswitch, DNS)
# - Connects to a server (specific, by country, or fastest)
# - Keeps the container running and disconnects on shutdown

log() { echo "[$(date -Iseconds)] $*"; }

cleanup() {
  log "Shutting down, attempting to disconnect..."
  if command -v protonvpn-cli >/dev/null 2>&1; then
    protonvpn-cli d || true
  fi
  exit 0
}
trap cleanup SIGINT SIGTERM

# Preflight checks
if ! command -v protonvpn-cli >/dev/null 2>&1; then
  log "ERROR: protonvpn-cli not found in PATH."
  exit 1
fi

if [[ ! -c /dev/net/tun ]]; then
  log "WARNING: /dev/net/tun not found. Ensure you run the container with --device /dev/net/tun and --cap-add=NET_ADMIN."
fi

pvpn() { protonvpn-cli "$@"; }

# Optional non-interactive login with env vars
if [[ -n "${PVPN_USERNAME:-}" && -n "${PVPN_PASSWORD:-}" ]]; then
  log "Logging in with provided credentials..."
  pvpn logout >/dev/null 2>&1 || true
  if pvpn --help 2>&1 | grep -q -- '--password'; then
    pvpn login --username "$PVPN_USERNAME" --password "$PVPN_PASSWORD" || {
      log "ERROR: Login failed with --password."
      exit 1
    }
  else
    # Fallback attempt (may not work on all versions)
    if ! printf '%s\n%s\n' "$PVPN_USERNAME" "$PVPN_PASSWORD" | pvpn login; then
      log "Non-interactive login failed; ensure an existing session or use interactive login."
    fi
  fi
else
  log "No PVPN_USERNAME/PVPN_PASSWORD provided; using existing protonvpn-cli session."
fi

# Apply configuration
PROTO="${PVPN_PROTOCOL:-udp}"
KS="${PVPN_KILLSWITCH:-on}"
DNS="${PVPN_DNS:-on}"

log "Configuring: protocol=${PROTO}, killswitch=${KS}, dns=${DNS}"
pvpn configure \
  --protocol "$PROTO" \
  --killswitch "$KS" \
  --dns "$DNS" \
  --auto-connect off \
  --ip-leak-protection on || true

# Connect according to preference
if [[ -n "${PVPN_SERVER:-}" ]]; then
  log "Connecting to server: $PVPN_SERVER"
  pvpn c -s "$PVPN_SERVER" -f
elif [[ -n "${PVPN_COUNTRY:-}" ]]; then
  log "Connecting to country: $PVPN_COUNTRY"
  pvpn c -c "$PVPN_COUNTRY" -f
else
  log "Connecting to fastest server..."
  pvpn c -f
fi

# Report status
pvpn status || true

# Keep container alive
log "VPN connected. Container is now idling."
sleep infinity &
wait $!