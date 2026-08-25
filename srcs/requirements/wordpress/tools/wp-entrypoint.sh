#!/bin/bash
set -e

# Make sure the directory exists as php-fgm needs it
mkdir -p /run/php
chown -R www-data:www-data /run/php

# Wait for MariaDB to be fully operational
echo "Waiting for MariaDB..."
until mariadb -h"${MYSQL_HOST:-mariadb}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; do
    sleep 2
done
echo "MariaDB is ready!"

# Download and install WordPress if not already present
if [ ! -f wp-config.php ]; then
    echo "Downloading WordPress..."
    wp core download --allow-root

    echo "Creating wp-config.php..."
    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${MYSQL_PASSWORD}" \
        --dbhost="${MYSQL_HOST:-mariadb}" \
        --allow-root

    echo "Installing WordPress core..."
    wp core install \
        --url="https://${DOMAIN_NAME:-mzary.42.fr}" \
        --title="${WP_TITLE:-Inception}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --allow-root

    echo "Creating standard user..."
    wp user create \
        "${WP_USER}" "${WP_USER_EMAIL}" \
        --user_pass="${WP_USER_PASSWORD}" \
        --role=author \
        --allow-root
fi

# Ensure correct file permissions for Nginx
chown -R www-data:www-data /var/www/html

# Start PHP-FPM in the foreground
echo "Starting PHP-FPM..."
exec php-fpm8.2 -F
