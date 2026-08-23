# Developer Documentation

## 1. Environment Setup

The project must be run inside a virtual machine.

### Prerequisites

- Docker
- Docker Compose
- Make
- Linux virtual machine

Configure the local domain in `/etc/hosts`:

    127.0.0.1 mzary.42.fr

The project uses `/home/mzary/data` for persistent data.

Create the directories if necessary:

    sudo mkdir -p /home/mzary/data/mariadb
    sudo mkdir -p /home/mzary/data/wordpress

## 2. Configuration

The Docker Compose configuration is located at:

    srcs/docker-compose.yml

Environment variables are stored in:

    srcs/.env

The `.env` file contains the domain name, database configuration and WordPress configuration.

Sensitive credentials must not be committed to the Git repository.

## 3. Building and Launching with Make

### Build and start

From the project root:

    make

This builds the Docker images and starts the containers in detached mode.

### Build only

    make build

### Start without rebuilding

    docker compose -f srcs/docker-compose.yml up -d

### Stop the project

    make down

### Rebuild

    make re

### Clean Docker resources

    make clean

### Remove persistent project data

    make fclean

`fclean` removes the persistent data stored under:

    /home/mzary/data/

Use it only when the database and WordPress files are no longer needed.

## 4. Building and Launching with Docker Compose

### Build the images

    docker compose -f srcs/docker-compose.yml build

Rebuild without using the build cache:

    docker compose -f srcs/docker-compose.yml build --no-cache

### Start the infrastructure

    docker compose -f srcs/docker-compose.yml up -d

### Build and start

    docker compose -f srcs/docker-compose.yml up -d --build

### Stop the containers

    docker compose -f srcs/docker-compose.yml stop

### Stop and remove the containers

    docker compose -f srcs/docker-compose.yml down

### Stop and remove containers and volumes

    docker compose -f srcs/docker-compose.yml down -v

Do not use `-v` if persistent data must be preserved.

### Restart the infrastructure

    docker compose -f srcs/docker-compose.yml restart

## 5. Managing Containers with Docker Compose

List the containers:

    docker compose -f srcs/docker-compose.yml ps

List containers including stopped containers:

    docker compose -f srcs/docker-compose.yml ps -a

View logs:

    docker compose -f srcs/docker-compose.yml logs

Follow logs:

    docker compose -f srcs/docker-compose.yml logs -f

View logs for one service:

    docker compose -f srcs/docker-compose.yml logs nginx
    docker compose -f srcs/docker-compose.yml logs wordpress
    docker compose -f srcs/docker-compose.yml logs mariadb

Follow logs for one service:

    docker compose -f srcs/docker-compose.yml logs -f nginx

Restart one service:

    docker compose -f srcs/docker-compose.yml restart nginx

Stop one service:

    docker compose -f srcs/docker-compose.yml stop nginx

Start one service:

    docker compose -f srcs/docker-compose.yml start nginx

Recreate a service:

    docker compose -f srcs/docker-compose.yml up -d --force-recreate nginx

## 6. Managing Containers with the Docker CLI

List running containers:

    docker ps

List all containers:

    docker ps -a

View container logs:

    docker logs nginx
    docker logs wordpress
    docker logs mariadb

Follow container logs:

    docker logs -f nginx

Inspect a container:

    docker inspect nginx

Open a shell inside a container:

    docker exec -it nginx /bin/bash
    docker exec -it wordpress /bin/bash
    docker exec -it mariadb /bin/bash

Check processes inside a container:

    docker top nginx
    docker top wordpress
    docker top mariadb

Stop a container:

    docker stop nginx

Start a stopped container:

    docker start nginx

Restart a container:

    docker restart nginx

Remove a stopped container:

    docker rm nginx

## 7. Managing Images

List project images:

    docker images

Inspect an image:

    docker image inspect nginx

Remove an image:

    docker image rm nginx

Remove unused images:

    docker image prune

Rebuild the project images:

    docker compose -f srcs/docker-compose.yml build --no-cache

## 8. Managing Volumes

List Docker volumes:

    docker volume ls

Inspect a volume:

    docker volume inspect inception_mariadb_data
    docker volume inspect inception_wordpress_data

The exact volume names can be checked with:

    docker volume ls

List volumes used by the Compose project:

    docker compose -f srcs/docker-compose.yml config --volumes

Remove a specific volume:

    docker volume rm inception_mariadb_data

Remove all unused volumes:

    docker volume prune

Remove the Compose containers and their volumes:

    docker compose -f srcs/docker-compose.yml down -v

## 9. Persistent Data

The project uses two named Docker volumes.

MariaDB:

    mariadb_data
    /home/mzary/data/mariadb

WordPress:

    wordpress_data
    /home/mzary/data/wordpress

The host directories contain the persistent data used by the containers.

Check the data:

    ls -la /home/mzary/data/mariadb
    ls -la /home/mzary/data/wordpress

The data remains available when containers are stopped or recreated.

## 10. Network Management

The services communicate through the `inception` Docker network.

List networks:

    docker network ls

Inspect the project network:

    docker network inspect inception

The containers can communicate using their service names, for example:

    wordpress:9000
    mariadb:3306

The NGINX container is the only service exposed to the host through port 443.

## 11. Checking the Infrastructure

Check all services:

    docker compose -f srcs/docker-compose.yml ps

Check logs:

    docker compose -f srcs/docker-compose.yml logs

Check the network:

    docker network inspect inception

Check volumes:

    docker compose -f srcs/docker-compose.yml config --volumes

Check the published ports:

    docker ps

The expected external entry point is:

    https://mzary.42.fr

## 12. Project Structure

    .
    ├── DEV_DOC.md
    ├── Makefile
    ├── README.md
    ├── USER_DOC.md
    └── srcs
        ├── .env
        ├── docker-compose.yml
        └── requirements
            ├── mariadb
            │   ├── Dockerfile
            │   └── tools
            │       └── mariadb-entrypoint.sh
            ├── nginx
            │   ├── conf
            │   │   └── nginx.conf
            │   ├── Dockerfile
            │   └── tools
            │       └── nginx-entrypoint.sh
            └── wordpress
                ├── Dockerfile
                └── tools
                    └── wp-entrypoint.sh
