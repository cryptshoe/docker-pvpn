# Minimal WireGuard-based Proton VPN container
FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

# Install only what is needed for WireGuard
RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iproute2 \
    iptables \
    resolvconf \
    ca-certificates \
    iputils-ping \
    && rm -rf /var/lib/apt/lists/*

# Copy WireGuard entrypoint
COPY start_wireguard.sh /start_wireguard.sh
RUN chmod +x /start_wireguard.sh

# Default command starts WireGuard using configs mounted at /wireguard
CMD ["/start_wireguard.sh"]
