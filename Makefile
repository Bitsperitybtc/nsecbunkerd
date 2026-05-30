SHELL := /bin/bash

# --- Profiles ---------------------------------------------------------------
# PROFILE=default (production-ish) or PROFILE=local (isolated test stack).
# A profile is just a bundle of preset defaults; override any var on the CLI:
#   make setup PROFILE=local HOST_PORT=4000 KEY_NAME=test@local
PROFILE ?= default

ifeq ($(PROFILE),local)
  CONFIG_DIR ?= $(HOME)/.nsecbunker-config-local
  PROJECT    ?= nsecbunker-local
  HOST_PORT  ?= 3019
  RELAY      ?= ws://localhost:7777
  RELAY_SMOKE_URL ?= ws://relay:8080
  export COMPOSE_PROFILES := local
else
  CONFIG_DIR ?= $(HOME)/.nsecbunker-config
  PROJECT    ?= nsecbunker
  HOST_PORT  ?= 3009
endif

# --- Overridable knobs ------------------------------------------------------
KEY_NAME   ?= bitspark@local
RELAY      ?= wss://nos.lol
RELAY_SMOKE_URL ?= $(RELAY)
KEYGEN     ?= generic
ADMIN_NPUBS ?=

# --- Exported to docker compose (interpolated in docker-compose.yml) --------
export NSECBUNKER_CONFIG_DIR := $(CONFIG_DIR)
export NSECBUNKER_HOST_PORT  := $(HOST_PORT)
export COMPOSE_PROJECT_NAME  := $(PROJECT)

DC := docker compose

.PHONY: help keygen setup build up down restart logs ps connection teardown relay-smoke

help:
	@echo "nsecBunker — make targets"
	@echo ""
	@echo "  make keygen      Generate a signing identity inside the container"
	@echo "                   (KEYGEN=generic [default, Node crypto] | nostr [nostr-tools])"
	@echo "  make setup       Full guided setup: .env, signing key import, relays,"
	@echo "                   web-auth settings, start, and web-auth user"
	@echo "  make build       Build the local image"
	@echo "  make up|down|restart   Manage the stack"
	@echo "  make logs|ps           Inspect the stack"
	@echo "  make connection        Print connection.txt and admin-connection.txt"
	@echo "  make relay-smoke       Publish + read back an event on the local relay (PROFILE=local)"
	@echo "  make teardown          Stop the stack and (optionally) remove the config dir"
	@echo ""
	@echo "Profiles: PROFILE=default | local. Override knobs on the CLI, e.g.:"
	@echo "  make setup PROFILE=local HOST_PORT=4000 KEY_NAME=test@local KEYGEN=nostr"
	@echo ""
	@echo "Active: PROFILE=$(PROFILE) dir=$(CONFIG_DIR) port=$(HOST_PORT) project=$(PROJECT)"
	@echo "        key=$(KEY_NAME) relay=$(RELAY)"

keygen:
	@mkdir -p "$(CONFIG_DIR)"
	@$(DC) run --rm --no-deps -e KEYGEN=$(KEYGEN) --entrypoint sh nsecbunkerd /app/scripts/keygen.sh

setup:
	@KEY_NAME="$(KEY_NAME)" RELAY="$(RELAY)" ADMIN_NPUBS="$(ADMIN_NPUBS)" bash scripts/setup.sh

build:
	$(DC) build nsecbunkerd

up:
	$(DC) up -d

down:
	$(DC) down

restart:
	$(DC) restart

logs:
	$(DC) logs -f --tail=100

ps:
	$(DC) ps

connection:
	@$(DC) exec -T nsecbunkerd cat /app/config/connection.txt; echo
	@$(DC) exec -T nsecbunkerd cat /app/config/admin-connection.txt; echo

relay-smoke:
	@$(DC) up -d relay
	@$(DC) run --rm --no-deps \
		-v "$(CURDIR)/scripts:/app/scripts:ro" \
		-e RELAY_URL="$(RELAY_SMOKE_URL)" --entrypoint node nsecbunkerd \
		/app/scripts/relay-smoke.mjs

teardown:
	-$(DC) down -v
	@read -r -p "Remove config dir $(CONFIG_DIR)? [y/N] " ans; \
	if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
		rm -rf "$(CONFIG_DIR)" && echo "removed $(CONFIG_DIR)"; \
	else \
		echo "kept $(CONFIG_DIR)"; \
	fi
