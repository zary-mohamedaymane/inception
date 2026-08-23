*This project has been created as part of the 42 curriculum by mzary.*

# Inception

## Description

Inception is a system administration project that builds a small infrastructure using Docker Compose inside a virtual machine.

The infrastructure consists of three services:

- NGINX with TLS 1.2/1.3
- WordPress with PHP-FPM
- MariaDB

WordPress and MariaDB use persistent Docker named volumes.

## Instructions

### Prerequisites

- Linux virtual machine
- Docker
- Docker Compose
- Add the following entry to `/etc/hosts`:

    127.0.0.1 mzary.42.fr

### Start

    make

### Stop

    make down

### Rebuild

    make re

The website is available at:

    https://mzary.42.fr

The WordPress administration panel is available at:

    https://mzary.42.fr/wp-admin

## Project description

### Architecture

    Client
       |
       | HTTPS :443
       v
    NGINX
       |
       | FastCGI :9000
       v
    WordPress + PHP-FPM
       |
       | MariaDB :3306
       v
    MariaDB

All containers communicate through a dedicated Docker bridge network.

### Design Choices

#### Virtual Machines vs Docker

A virtual machine runs a complete operating system with its own kernel. Docker containers share the host kernel and isolate applications and their dependencies. Docker is lighter and is appropriate for this multi-service infrastructure.

#### Secrets vs Environment Variables

Environment variables are useful for configuration, but sensitive credentials should preferably be stored using Docker secrets. This project uses environment variables for its configuration.

#### Docker Network vs Host Network

A Docker network provides isolated communication between containers. Host networking removes this isolation by using the host network stack. This project uses a dedicated Docker bridge network.

#### Docker Volumes vs Bind Mounts

Docker volumes are managed by Docker and provide persistent storage for containers. Bind mounts directly map host paths into containers. This project uses named Docker volumes backed by `/home/mzary/data`.

## Resources

- Docker documentation
- Docker Compose documentation
- NGINX documentation
- PHP-FPM documentation
- WordPress documentation
- MariaDB documentation

AI was used to assist with understanding Docker, Docker Compose, NGINX, PHP-FPM and MariaDB, and to review configurations and documentation. All generated suggestions were reviewed and tested.

## Persistent Data

MariaDB data:

    /home/mzary/data/mariadb

WordPress files:

    /home/mzary/data/wordpress
