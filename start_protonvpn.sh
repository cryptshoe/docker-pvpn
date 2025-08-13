#!/usr/bin/env bash
set -euo pipefail

# ProtonVPN Docker Entrypoint
# - Optionally logs in using PVPN_USERNAME/PVPN_PASSWORD
# - Applies configuration (protocol, killswitch, DNS)
# - Connects to a server (specific, by country, or fastest)
# - Keeps the container running and disconnects on shutdown

log() { echo "[$(date -Iseconds)] $*"; }

# Ensure a D-Bus session exists for keyring/ProtonVPN CLI
if [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
  if command -v dbus-run-session >/dev/null 2>&1; then
    exec dbus-run-session -- "$0" "$@"
  elif command -v dbus-daemon >/dev/null 2>&1; then
    # Fallback: start a session bus manually and export address
    eval "$(dbus-daemon --session --fork --print-address=1 --print-pid=1)"
  else
    echo "[$(date -Iseconds)] WARNING: No D-Bus available; protonvpn-cli may fail." >&2
  fi
fi

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
# Try new-style config flags if supported; otherwise fall back to specific subcommands
if pvpn config --help 2>/dev/null | grep -q -- "--protocol"; then
  pvpn config \
    --protocol "$PROTO" \
    --killswitch "$KS" \
    --dns "$DNS" \
    --auto-connect off \
    --ip-leak-protection on || true
else
  # Fallbacks for older/newer CLI variants
  if pvpn ks --help >/dev/null 2>&1; then
    case "$KS" in
      on|ON|On) pvpn ks --on || true ;;
      off|OFF|Off) pvpn ks --off || true ;;
    esac
  fi
  # No reliable non-interactive flag for DNS across versions; rely on defaults
  :
fi

# Connect according to preference
if [[ -n "${PVPN_SERVER:-}" ]]; then
  log "Connecting to server: $PVPN_SERVER"
  pvpn c -s "$PVPN_SERVER" -f -p "$PROTO"
elif [[ -n "${PVPN_COUNTRY:-}" ]]; then
  log "Connecting to country: $PVPN_COUNTRY"
  pvpn c -c "$PVPN_COUNTRY" -f -p "$PROTO"
else
  log "Connecting to fastest server..."
  pvpn c -f -p "$PROTO"
fi

# Report status
pvpn status || true

# Keep container alive
log "VPN connected. Container is now idling."
sleep infinity &
wait $!