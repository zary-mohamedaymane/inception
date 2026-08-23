# User Documentation

## Services

The project provides three services:

- NGINX: HTTPS entry point.
- WordPress: Website and administration interface.
- MariaDB: Database used by WordPress.

## Start and Stop

Start the project:

    make

Stop the project:

    make down

Rebuild the project:

    make re

## Accessing WordPress

Website:

    https://mzary.42.fr

Administration panel:

    https://mzary.42.fr/wp-admin

The TLS certificate is self-signed, so the browser may display a certificate warning.

## Credentials

Project configuration and credentials are stored locally in the environment configuration.

Sensitive credentials must not be committed to the Git repository.

## Checking the Services

Check the running containers:

    docker compose -f srcs/docker-compose.yml ps

View service logs:

    docker compose -f srcs/docker-compose.yml logs

Check persistent data:

    ls -la /home/mzary/data/
