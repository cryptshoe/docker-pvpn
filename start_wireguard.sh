#!/usr/bin/env bash
set -euo pipefail

# WireGuard-based Proton VPN Entrypoint
# - Picks a WireGuard .conf file from a directory by server or country code
# - Optionally appends IPv6 (::/0) to AllowedIPs
# - Optionally strips DNS= lines to avoid resolvconf/systemd-resolved requirements in containers
# - Copies to /etc/wireguard/wg0.conf and brings up the interface via wg-quick
# - Keeps the container running and brings the interface down on shutdown

log() { echo "[$(date -Iseconds)] $*"; }

cleanup() {
  log "Shutting down, bringing WireGuard interface down..."
  if command -v wg-quick >/dev/null 2>&1; then
    wg-quick down wg0 || true
  fi
  # Restore resolv.conf if we modified it
  if [[ -n "${RESOLV_CONF_BACKUP:-}" && -f "$RESOLV_CONF_BACKUP" && -w /etc/resolv.conf ]]; then
    log "Restoring /etc/resolv.conf"
    cp -f "$RESOLV_CONF_BACKUP" /etc/resolv.conf || true
    rm -f "$RESOLV_CONF_BACKUP" || true
  fi
  exit 0
}
trap cleanup SIGINT SIGTERM

# Preflight checks
if ! command -v wg-quick >/dev/null 2>&1; then
  log "ERROR: wg-quick not found. Install wireguard-tools in the image."
  exit 1
fi
if ! command -v wg >/dev/null 2>&1; then
  log "WARNING: wg not found; status output will be limited. Install wireguard-tools for full visibility."
fi

if [[ ! -c /dev/net/tun ]]; then
  log "ERROR: /dev/net/tun not found. Run the container with --device /dev/net/tun and --cap-add=NET_ADMIN."
  exit 1
fi

# Configuration sources
WG_DIR="${PVPN_WG_DIR:-/wireguard}"
STRATEGY="${PVPN_WG_STRATEGY:-first}"   # first|random
ENABLE_IPV6="${PVPN_IPV6:-off}"         # on|off -> appends ::/0 when on
WG_DNS="${PVPN_WG_DNS:-on}"             # on|off -> strip DNS= lines when off
EXPLICIT_NAME="${PVPN_WG_NAME:-}"       # explicit .conf name or basename
SERVER_CODE="${PVPN_SERVER:-}"          # e.g., swiss1-CH-5 (basename without .conf)
COUNTRY_CODE_RAW="${PVPN_COUNTRY:-}"    # e.g., CH, US, DE

# Normalize country code to uppercase if provided
COUNTRY_CODE="${COUNTRY_CODE_RAW^^}"

# Ensure config directory exists and has .conf files
if [[ ! -d "$WG_DIR" ]]; then
  log "ERROR: Config directory not found: $WG_DIR"
  exit 1
fi
shopt -s nullglob
mapfile -t ALL_CONFS < <(ls -1 "$WG_DIR"/*.conf 2>/dev/null || true)
shopt -u nullglob
if (( ${#ALL_CONFS[@]} == 0 )); then
  log "ERROR: No .conf files found in $WG_DIR. Place Proton WireGuard configs there."
  exit 1
fi

pick_conf() {
  local choice=""
  local candidates=()

  # 1) Explicit name
  if [[ -n "$EXPLICIT_NAME" ]]; then
    if [[ -f "$WG_DIR/$EXPLICIT_NAME" ]]; then
      choice="$WG_DIR/$EXPLICIT_NAME"
      echo "$choice"
      return 0
    fi
    if [[ -f "$WG_DIR/$EXPLICIT_NAME.conf" ]]; then
      choice="$WG_DIR/$EXPLICIT_NAME.conf"
      echo "$choice"
      return 0
    fi
    log "ERROR: Explicit config not found: $EXPLICIT_NAME"
    return 1
  fi

  # 2) Server code (basename)
  if [[ -n "$SERVER_CODE" ]]; then
    if [[ -f "$WG_DIR/$SERVER_CODE.conf" ]]; then
      echo "$WG_DIR/$SERVER_CODE.conf"
      return 0
    fi
    # Allow partial match by prefix
    shopt -s nullglob nocaseglob
    candidates=("$WG_DIR/${SERVER_CODE}"*.conf)
    shopt -u nocaseglob
    if (( ${#candidates[@]} > 0 )); then
      echo "${candidates[0]}"
      return 0
    fi
    log "ERROR: No config matched server code: $SERVER_CODE"
    return 1
  fi

  # 3) Country code
  if [[ -n "$COUNTRY_CODE" ]]; then
    shopt -s nullglob nocaseglob
    # Prefer pattern *-CC-*.conf
    candidates=("$WG_DIR"/*-"$COUNTRY_CODE"-*.conf)
    if (( ${#candidates[@]} == 0 )); then
      # Fallback: any file containing the code
      candidates=("$WG_DIR"/*"$COUNTRY_CODE"*.conf)
    fi
    shopt -u nocaseglob

    if (( ${#candidates[@]} == 0 )); then
      log "ERROR: No configs found for country code: $COUNTRY_CODE"
      return 1
    fi

    if [[ "$STRATEGY" =~ ^rand(om)?$ ]]; then
      if command -v shuf >/dev/null 2>&1; then
        choice="$(printf '%s\n' "${candidates[@]}" | shuf -n 1)"
      else
        choice="${candidates[0]}"
      fi
    else
      choice="${candidates[0]}"
    fi
    echo "$choice"
    return 0
  fi

  # 4) Single file fallback
  if (( ${#ALL_CONFS[@]} == 1 )); then
    echo "${ALL_CONFS[0]}"
    return 0
  fi

  log "ERROR: Multiple configs present. Specify PVPN_SERVER, PVPN_WG_NAME, or PVPN_COUNTRY."
  return 1
}

CONF_SRC="$(pick_conf)" || exit 1
log "Selected WireGuard config: $CONF_SRC"

# Prepare destination and normalize interface name to avoid long-name issues
mkdir -p /etc/wireguard
CONF_DST="/etc/wireguard/wg0.conf"

# Start from source content
CONF_CONTENT="$(cat "$CONF_SRC")"

# Extract DNS servers from the original config (space-separated)
DNS_SERVERS=""
if grep -qE '^DNS\s*=' <<<"$CONF_CONTENT"; then
  DNS_SERVERS="$(awk -F'=' '/^DNS[[:space:]]*=/ {v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(",", " ", v); print v}' <<<"$CONF_CONTENT" | xargs)"
fi

# Optionally add IPv6 ::/0 to AllowedIPs if not present
if [[ "$ENABLE_IPV6" =~ ^(on|true|1|yes)$ ]]; then
  if ! grep -qE '^AllowedIPs\s*=.*::/0' <<<"$CONF_CONTENT"; then
    CONF_CONTENT="$(sed -E \
      -e '/^AllowedIPs[[:space:]]*=/ { /::\\/0/! s/$/, ::\\/0/; }' \
      <<<"$CONF_CONTENT")"
    log "Enabled IPv6 routing (::/0) in AllowedIPs"
  fi
fi

# Always remove DNS lines to avoid wg-quick calling resolvconf/systemd-resolved in containers
if grep -qE '^DNS\s*=' <<<"$CONF_CONTENT"; then
  CONF_CONTENT="$(sed -E -e '/^DNS[[:space:]]*=.*/d' <<<"$CONF_CONTENT")"
  log "Removed DNS= lines from config to avoid resolvconf"
fi

# Write final config
printf '%s\n' "$CONF_CONTENT" > "$CONF_DST"
chmod 600 "$CONF_DST"

# Bring up WireGuard
log "Bringing up WireGuard interface: wg0"
wg-quick up wg0

# Apply DNS by writing /etc/resolv.conf directly when enabled
if [[ "$WG_DNS" =~ ^(on|true|1|yes)$ && -n "${DNS_SERVERS:-}" ]]; then
  if [ -w /etc/resolv.conf ]; then
    RESOLV_CONF_BACKUP="/etc/resolv.conf.pvpn-backup"
    if [ ! -f "$RESOLV_CONF_BACKUP" ]; then
      cp -f /etc/resolv.conf "$RESOLV_CONF_BACKUP" || true
    fi
    {
      for ns in $DNS_SERVERS; do
        echo "nameserver $ns"
      done
    } > /etc/resolv.conf || true
    chmod 644 /etc/resolv.conf || true
    log "Applied DNS servers to /etc/resolv.conf: $DNS_SERVERS"
  else
    log "WARNING: /etc/resolv.conf is not writable; cannot apply DNS"
  fi
fi

# Status
if command -v wg >/dev/null 2>&1; then
  wg show
else
  ip addr show wg0 || true
fi

log "WireGuard connected. Container is now idling."
sleep infinity &
wait $!
