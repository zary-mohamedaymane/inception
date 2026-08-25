FROM debian:bookworm-slim

# Install Nginx, OpenSSL, and netcat (for health checks)
RUN apt-get update && \
    apt-get install -y \
    nginx \
    openssl \
    netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

# Copy configuration and entrypoint script
COPY conf/nginx.conf /etc/nginx/conf.d/default.conf
COPY tools/nginx-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/nginx-entrypoint.sh

EXPOSE 443

ENTRYPOINT ["nginx-entrypoint.sh"]
