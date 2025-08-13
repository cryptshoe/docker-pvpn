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
    # ProtonVPN runtime deps
    openvpn \
    wireguard-tools \
    iproute2 \
    iptables \
    resolvconf \
    && rm -rf /var/lib/apt/lists/*

# Add ProtonVPN repository (pattern retained from your setup)
RUN curl -s https://repo.protonvpn.com/debian/public_key.asc | apt-key add - && \
    add-apt-repository "deb https://repo.protonvpn.com/debian unstable main"

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