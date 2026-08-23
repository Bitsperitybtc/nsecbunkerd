SHELL := /bin/bash

# --- Profiles ---------------------------------------------------------------
# A profile is a config-file bundle in profiles/<name>.env. Pick one with
# PROFILE=<name>; every variable can still be overridden on the CLI, e.g.:
#   make setup PROFILE=local HOST_PORT=4000 KEY_NAME=test@local
# Add a new identity by copying profiles/local.env to profiles/<name>.env.
PROFILE ?= default

PROFILES := $(patsubst profiles/%.env,%,$(wildcard profiles/*.env))
PROFILE_FILE := profiles/$(PROFILE).env
ifeq ($(wildcard $(PROFILE_FILE)),)
  $(error Unknown profile '$(PROFILE)': $(PROFILE_FILE) not found. Available: $(PROFILES))
endif
include $(PROFILE_FILE)

# --- Non-profile defaults ---------------------------------------------------
KEYGEN ?= generic

# Start the bundled local relay (and the smoke target) only when the profile
# opts in with LOCAL_RELAY=1. The Compose service is tagged `profiles: [local]`.
ifeq ($(LOCAL_RELAY),1)
  export COMPOSE_PROFILES := local
endif

# --- Exported to docker compose (interpolated in docker-compose.yml) --------
export NSECBUNKER_CONFIG_DIR := $(CONFIG_DIR)
export NSECBUNKER_HOST_PORT  := $(HOST_PORT)
export COMPOSE_PROJECT_NAME  := $(PROJECT)
export SIGNER_IDENTITY_FILE  := $(SIGNER_IDENTITY_FILE)
export RELAY_HOST_PORT       := $(RELAY_HOST_PORT)
export NSECBUNKER_KEY_NAME   := $(KEY_NAME)
export DOCKER_UID            := $(shell id -u)
export DOCKER_GID            := $(shell id -g)
ifneq ($(strip $(ADMIN_NPUBS)),)
export ADMIN_NPUBS
endif

DC := docker compose

.PHONY: help keygen setup build up down restart logs ps connection web-auth-password patch-config teardown relay-smoke profile-create profile-setup profile-destroy

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
	@echo "  make patch-config      Re-apply relay/baseUrl settings from the active profile"
	@echo "  make web-auth-password Reset the browser approval page password (WEB_AUTH_PASSWORD=...)"
	@echo "  make relay-smoke       Publish + read back an event on the local relay (PROFILE=local)"
	@echo "  make teardown          Stop the stack and (optionally) remove the config dir"
	@echo "  make profile-create    Create a disposable profile (NAME=pc2)"
	@echo "  make profile-setup     Create + keygen + setup in one shot (NAME=pc2)"
	@echo "  make profile-destroy   Stop and remove profile (NAME=pc2 YES=1)"
	@echo ""
	@echo "Profiles (profiles/<name>.env): $(PROFILES)"
	@echo "Pick with PROFILE=<name>; override any knob on the CLI, e.g.:"
	@echo "  make setup PROFILE=local HOST_PORT=4000 KEY_NAME=test@local KEYGEN=nostr"
	@echo ""
	@echo "Active: PROFILE=$(PROFILE) dir=$(CONFIG_DIR) port=$(HOST_PORT) project=$(PROJECT)"
	@echo "        key=$(KEY_NAME) relay=$(RELAY) clientRelay=$(CLIENT_RELAY) baseUrl=$(PUBLIC_BASE_URL)"
	@echo "        signer=$(SIGNER_IDENTITY_FILE) localRelay=$(LOCAL_RELAY)"

keygen:
	@mkdir -p "$(CONFIG_DIR)"
	@$(DC) run --rm --no-deps -e KEYGEN=$(KEYGEN) --entrypoint sh nsecbunkerd /app/scripts/keygen.sh

setup:
	@KEY_NAME="$(KEY_NAME)" RELAY="$(RELAY)" CLIENT_RELAY="$(CLIENT_RELAY)" \
	  PUBLIC_BASE_URL="$(PUBLIC_BASE_URL)" ADMIN_NPUBS="$(ADMIN_NPUBS)" \
	  SIGNER_IDENTITY_FILE="$(SIGNER_IDENTITY_FILE)" bash scripts/setup.sh

patch-config:
	@echo "==> patching config (PROFILE=$(PROFILE))"
	@$(DC) run --rm -T --no-deps --entrypoint "" \
	  -e NSECBUNKER_RELAY="$(RELAY)" \
	  -e NSECBUNKER_CLIENT_RELAY="$(CLIENT_RELAY)" \
	  -e NSECBUNKER_PUBLIC_BASE_URL="$(PUBLIC_BASE_URL)" \
	  -e NSECBUNKER_HOST_PORT="$(HOST_PORT)" \
	  nsecbunkerd node /app/scripts/patch-config.mjs
	@echo "==> restart nsecbunkerd to regenerate connection.txt"
	@$(DC) restart nsecbunkerd

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
	@if ! $(DC) ps --status running -q nsecbunkerd 2>/dev/null | grep -q .; then \
	  echo "nsecbunkerd is not running for PROFILE=$(PROFILE) (project=$(PROJECT))." >&2; \
	  echo "Available profiles: $(PROFILES)" >&2; \
	  echo "Start it with: make up PROFILE=$(PROFILE)" >&2; \
	  exit 1; \
	fi
	@$(DC) exec -T nsecbunkerd node /app/scripts/write-connection-uris.mjs 2>/dev/null || true
	@$(DC) exec -T nsecbunkerd cat /app/config/connection.txt; echo
	@$(DC) exec -T nsecbunkerd cat /app/config/admin-connection.txt; echo

web-auth-password:
	@if [ -z "$${WEB_AUTH_PASSWORD:-}" ]; then \
	  read -r -s -p "New web auth password: " WEB_AUTH_PASSWORD; echo; \
	fi; \
	$(DC) exec -T -e WEB_AUTH_PASSWORD="$$WEB_AUTH_PASSWORD" nsecbunkerd \
	  node /app/scripts/create-web-auth-user.mjs

relay-smoke:
	@$(DC) up -d relay
	@$(DC) run --rm --no-deps \
		-v "$(CURDIR)/scripts:/app/scripts:ro" \
		-e RELAY_URL="$(RELAY_SMOKE_URL)" --entrypoint node nsecbunkerd \
		/app/scripts/relay-smoke.mjs

teardown:
	-$(DC) down -v
	@if [ "$(YES)" = "1" ]; then \
	  rm -rf "$(CONFIG_DIR)" && echo "removed $(CONFIG_DIR)"; \
	else \
	  read -r -p "Remove config dir $(CONFIG_DIR)? [y/N] " ans; \
	  if [ "$$ans" = "y" ] || [ "$$ans" = "Y" ]; then \
	    rm -rf "$(CONFIG_DIR)" && echo "removed $(CONFIG_DIR)"; \
	  else \
	    echo "kept $(CONFIG_DIR)"; \
	  fi; \
	fi

profile-create:
	@if [ -z "$(NAME)" ]; then echo "NAME is required (e.g. make profile-create NAME=pc2)" >&2; exit 1; fi
	@$(if $(filter command line,$(origin HOST_PORT)),export PROFILE_HOST_PORT=$(HOST_PORT);) \
	$(if $(filter command line,$(origin RELAY_HOST_PORT)),export PROFILE_RELAY_HOST_PORT=$(RELAY_HOST_PORT);) \
	$(if $(filter command line,$(origin DEV_HOST)),export DEV_HOST=$(DEV_HOST);) \
	NAME="$(NAME)" bash scripts/profile.sh create

profile-setup:
	@if [ -z "$(NAME)" ]; then echo "NAME is required (e.g. make profile-setup NAME=pc2)" >&2; exit 1; fi
	@$(if $(filter command line,$(origin ADMIN_NPUBS)),export ADMIN_NPUBS=$(ADMIN_NPUBS);) \
	NAME="$(NAME)" KEYGEN="$(KEYGEN)" bash scripts/profile.sh setup

profile-destroy:
	@if [ -z "$(NAME)" ]; then echo "NAME is required (e.g. make profile-destroy NAME=pc2)" >&2; exit 1; fi
	@NAME="$(NAME)" YES="$(YES)" bash scripts/profile.sh destroy
