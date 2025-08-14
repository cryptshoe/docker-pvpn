#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date -Iseconds)] $*"; }

cleanup() {
  log "Shutting down, bringing WireGuard interface down..."
  if command -v wg-quick >/dev/null 2>&1; then
    wg-quick down wg0 || true
  fi
  if [[ -n "${RESOLV_CONF_BACKUP:-}" && -f "$RESOLV_CONF_BACKUP" && -w /etc/resolv.conf ]]; then
    log "Restoring /etc/resolv.conf"
    cp -f "$RESOLV_CONF_BACKUP" /etc/resolv.conf || true
    rm -f "$RESOLV_CONF_BACKUP" || true
  fi
}
trap cleanup SIGINT SIGTERM EXIT

# -------------------
# Preflight
# -------------------
if ! command -v wg-quick >/dev/null 2>&1; then
  log "ERROR: wg-quick not installed."
  exit 1
fi
if [[ ! -c /dev/net/tun ]]; then
  log "ERROR: /dev/net/tun missing. Run with --device /dev/net/tun --cap-add=NET_ADMIN."
  exit 1
fi

WG_DIR="${PVPN_WG_DIR:-/wireguard}"
STRATEGY="${PVPN_WG_STRATEGY:-first}"
ENABLE_IPV6="${PVPN_IPV6:-off}"
WG_DNS_FLAG="${PVPN_WG_DNS:-on}"
EXPLICIT_NAME="${PVPN_WG_NAME:-}"
SERVER_CODE="${PVPN_SERVER:-}"
COUNTRY_CODE="${PVPN_COUNTRY^^:-}"

# -------------------
# Pick config
# -------------------
shopt -s nullglob
mapfile -t ALL_CONFS < <(ls -1 "$WG_DIR"/*.conf 2>/dev/null || true)
shopt -u nullglob
if (( ${#ALL_CONFS[@]} == 0 )); then
  log "ERROR: No configs found in $WG_DIR"
  exit 1
fi

pick_conf() {
  local choice=""
  local candidates=()

  if [[ -n "$EXPLICIT_NAME" ]]; then
    [[ -f "$WG_DIR/$EXPLICIT_NAME" ]] && { echo "$WG_DIR/$EXPLICIT_NAME"; return; }
    [[ -f "$WG_DIR/$EXPLICIT_NAME.conf" ]] && { echo "$WG_DIR/$EXPLICIT_NAME.conf"; return; }
    log "ERROR: Explicit config not found: $EXPLICIT_NAME"; return 1
  fi

  if [[ -n "$SERVER_CODE" ]]; then
    [[ -f "$WG_DIR/$SERVER_CODE.conf" ]] && { echo "$WG_DIR/$SERVER_CODE.conf"; return; }
    shopt -s nullglob nocaseglob
    candidates=("$WG_DIR/${SERVER_CODE}"*.conf)
    shopt -u nocaseglob
    (( ${#candidates[@]} > 0 )) && { echo "${candidates[0]}"; return; }
    log "ERROR: No match for server code: $SERVER_CODE"; return 1
  fi

  if [[ -n "$COUNTRY_CODE" ]]; then
    shopt -s nullglob nocaseglob
    candidates=("$WG_DIR"/*-"$COUNTRY_CODE"-*.conf)
    (( ${#candidates[@]} == 0 )) && candidates=("$WG_DIR"/*"$COUNTRY_CODE"*.conf)
    shopt -u nocaseglob
    (( ${#candidates[@]} == 0 )) && { log "ERROR: No configs for country: $COUNTRY_CODE"; return 1; }
    [[ "$STRATEGY" =~ ^rand(om)?$ ]] && choice=$(printf '%s\n' "${candidates[@]}" | shuf -n 1) || choice="${candidates[0]}"
    echo "$choice"; return
  fi

  (( ${#ALL_CONFS[@]} == 1 )) && { echo "${ALL_CONFS[0]}"; return; }
  log "ERROR: Multiple configs; set PVPN_SERVER, PVPN_WG_NAME, or PVPN_COUNTRY."; return 1
}

CONF_SRC="$(pick_conf)" || exit 1
log "Selected WireGuard config: $CONF_SRC"

mkdir -p /etc/wireguard
CONF_DST="/etc/wireguard/wg0.conf"
CONF_CONTENT="$(cat "$CONF_SRC")"

# Extract DNS from config
DNS_SERVERS=""
if grep -qE '^DNS\s*=' <<<"$CONF_CONTENT"; then
  DNS_SERVERS="$(awk -F'=' '/^DNS[[:space:]]*=/ {v=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); gsub(",", " ", v); print v}' <<<"$CONF_CONTENT" | xargs)"
fi

# IPv6 if enabled
if [[ "$ENABLE_IPV6" =~ ^(on|true|1|yes)$ ]]; then
  if ! grep -qE '^AllowedIPs\s*=.*::/0' <<<"$CONF_CONTENT"; then
    CONF_CONTENT="$(sed -E '/^AllowedIPs[[:space:]]*=/ { /::\/0/! s/$/, ::\/0/; }' <<<"$CONF_CONTENT")"
    log "Added ::/0 to AllowedIPs"
  fi
fi

# Remove DNS= from config, we set manually
CONF_CONTENT="$(sed -E '/^DNS[[:space:]]*=.*/d' <<<"$CONF_CONTENT")"

printf '%s\n' "$CONF_CONTENT" > "$CONF_DST"
chmod 600 "$CONF_DST"

# -------------------
# Bring up WireGuard
# -------------------
log "Starting WireGuard"
wg-quick up wg0

# Main interface name (detect dynamically)
MAIN_IF=$(ip route show default | awk '/default/ {print $5}' | head -n1)

# -------------------
# Enable forwarding
# -------------------
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1 || true

# -------------------
# Clean iptables
# -------------------
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# -------------------
# Forwarding rules
# -------------------
iptables -A FORWARD -i wg0 -o "$MAIN_IF" -j ACCEPT
iptables -A FORWARD -i "$MAIN_IF" -o wg0 -j ACCEPT

# -------------------
# MASQUERADE excluding all VPN DNS servers
# -------------------
for ns in $DNS_SERVERS; do
  iptables -t nat -A POSTROUTING -d "$ns" -o wg0 -j ACCEPT
  ip route add "$ns"/32 dev wg0 || true
done
iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE

# -------------------
# Prevent routing loop for WG endpoint
# -------------------
WG_ENDPOINT_IP=$(wg show wg0 endpoints | awk '{print $2}' | cut -d':' -f1 || true)
if [[ -n "$WG_ENDPOINT_IP" ]]; then
  GW=$(ip route show default dev "$MAIN_IF" | awk '{print $3}' || true)
  [[ -n "$GW" ]] && ip route add "$WG_ENDPOINT_IP"/32 via "$GW" dev "$MAIN_IF" || true
fi

# -------------------
# Policy routing for WireGuard fwmark
# -------------------
ip rule add not fwmark 0xca6c lookup 51820 || true
ip rule add table main suppress_prefixlength 0 || true
ip route add default dev wg0 table 51820 || true

# -------------------
# Apply VPN DNS to resolv.conf
# -------------------
if [[ "$WG_DNS_FLAG" =~ ^(on|true|1|yes)$ && -n "$DNS_SERVERS" ]]; then
  if [ -w /etc/resolv.conf ]; then
    RESOLV_CONF_BACKUP="/etc/resolv.conf.pvpn-backup"
    [ ! -f "$RESOLV_CONF_BACKUP" ] && cp -f /etc/resolv.conf "$RESOLV_CONF_BACKUP" || true
    {
      for ns in $DNS_SERVERS; do
        echo "nameserver $ns"
      done
    } > /etc/resolv.conf
    chmod 644 /etc/resolv.conf
    log "Applied DNS servers: $DNS_SERVERS"
  fi
fi

# -------------------
# Show status
# -------------------
log "Routing table:"
ip route
log "iptables NAT table:"
iptables -t nat -L -v
log "resolv.conf content:"
cat /etc/resolv.conf

# -------------------
# Start SOCKS5 proxy
# -------------------
PROXY_PORT="${PROXY_PORT:-1080}"
log "Starting SOCKS5 proxy on :$PROXY_PORT"
microsocks -p "$PROXY_PORT" -i 0.0.0.0 &

log "WireGuard and SOCKS5 proxy running."
sleep infinity &
wait $!
