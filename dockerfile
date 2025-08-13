FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    wireguard-tools \
    iproute2 \
    iptables \
    resolvconf \
    ca-certificates \
    iputils-ping \
    build-essential \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install microsocks from source (lightweight)
RUN git clone https://github.com/rofl0r/microsocks.git /microsocks && \
    cd /microsocks && \
    make && \
    cp microsocks /usr/local/bin/ && \
    cd / && \
    rm -rf /microsocks

COPY start_wireguard.sh /start_wireguard.sh
RUN chmod +x /start_wireguard.sh

CMD ["/start_wireguard.sh"]
