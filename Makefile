NAME = inception
COMPOSE = ./srcs/docker-compose.yml
DATA_PATH = /home/mzary/data

all: up

up: build
	@mkdir -p $(DATA_PATH)/wordpress $(DATA_PATH)/mariadb
	docker compose -f $(COMPOSE) up -d

build:
	docker compose -f $(COMPOSE) build

down:
	docker compose -f $(COMPOSE) down

re: clean up

clean: down
	docker system prune -a --volumes -f

fclean: clean
	rm -rf $(DATA_PATH)/wordpress/* $(DATA_PATH)/mariadb/*

.PHONY: all up build down re clean fclean
