# Use an Ubuntu base image
FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

# Update package list and install necessary packages
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    ca-certificates \
    software-properties-common \
    dbus-user-session \
    gnome-keyring \
    libsecret-1-0 \
    python3-secretstorage \
    # ProtonVPN runtime deps
    openvpn \
    wireguard-tools \
    iproute2 \
    iptables \
    resolvconf \
    && rm -rf /var/lib/apt/lists/*

# Add ProtonVPN repository using keyring (apt-key is deprecated)
RUN set -eux; \
    install -m 0755 -d /etc/apt/keyrings; \
    curl -fsSL https://repo.protonvpn.com/debian/public_key.asc | gpg --dearmor -o /etc/apt/keyrings/protonvpn.gpg; \
    chmod a+r /etc/apt/keyrings/protonvpn.gpg; \
    echo 'deb [signed-by=/etc/apt/keyrings/protonvpn.gpg] https://repo.protonvpn.com/debian unstable main' > /etc/apt/sources.list.d/protonvpn.list

# Install ProtonVPN CLI
RUN apt-get update && apt-get install -y protonvpn-cli && \
    rm -rf /var/lib/apt/lists/*

# Create a directory for configuration (optional)
RUN mkdir -p /etc/protonvpn

# Copy entry point script and make it executable
COPY start_protonvpn.sh /start_protonvpn.sh
RUN chmod +x /start_protonvpn.sh

# Note: Exposing a port is not needed for a VPN client container
# EXPOSE 1194

# Start ProtonVPN
CMD ["/start_protonvpn.sh"]