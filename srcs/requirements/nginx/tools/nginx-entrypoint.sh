#!/bin/bash
set -e

# Ensure runtime and SSL directories exist
mkdir -p /etc/ssl/certs /etc/ssl/private /run/nginx

# Generate SSL certificate if it doesn't exist
if [ ! -f /etc/ssl/certs/nginx-selfsigned.crt ]; then
    echo "Generating self-signed SSL certificate..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/nginx-selfsigned.key \
        -out /etc/ssl/certs/nginx-selfsigned.crt \
        -subj "/C=MA/ST=BeniMellal/L=Khouribga/O=1337/OU=student/CN=mzary.42.fr"
fi

# Wait for WordPress PHP-FPM container to be ready on port 9000
echo "Waiting for WordPress PHP-FPM to be ready..."
until nc -z -v -w3 wordpress 9000; do
    sleep 2
done
echo "WordPress PHP-FPM is up and listening!"

# Start Nginx in the foreground
exec nginx -g "daemon off;"
