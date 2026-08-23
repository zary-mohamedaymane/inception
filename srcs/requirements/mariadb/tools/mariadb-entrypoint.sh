#!/bin/bash
set -e

# Ensure the mysqld runtime directory exists with proper permissions
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld

# Check if the WordPress database directory already exists
if [ ! -d "/var/lib/mysql/${MYSQL_DATABASE}" ]; then
    echo "Initializing MariaDB data directory..."
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql > /dev/null

    echo "Running bootstrap configuration..."
    mysqld --bootstrap --user=mysql --datadir=/var/lib/mysql <<EOF
USE mysql;
FLUSH PRIVILEGES;

-- Set root password and grant permissions for root
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
GRANT ALL ON *.* TO 'root'@'localhost' WITH GRANT OPTION;

-- Create WordPress database
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;

-- Create WordPress user and grant privileges
CREATE USER '${MYSQL_USER}'@'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';

-- Clean up default anonymous users and test database
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF

    echo "Bootstrap configuration completed."
fi

# Start the actual production server in the foreground
exec mysqld --user=mysql --bind-address=0.0.0.0
