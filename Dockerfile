FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY bin/ziti-edge-tunnel /usr/local/bin/ziti-edge-tunnel
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/ziti-edge-tunnel /entrypoint.sh

VOLUME ["/etc/ziti"]
ENTRYPOINT ["/entrypoint.sh"]
