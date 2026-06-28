#!/usr/bin/env bash
# Profile lifecycle: create, setup, destroy arbitrary named stacks.
# Invoked via: make profile-create|profile-setup|profile-destroy NAME=<name>
set -euo pipefail

cd "$(dirname "$0")/.."

ACTION="${1:-}"
NAME="${NAME:-}"
RESERVED_PROFILES="default local"

usage() {
  echo "Usage: profile.sh {create|setup|destroy}" >&2
  exit 1
}

validate_name() {
  if [[ -z "$NAME" ]]; then
    echo "NAME is required (e.g. make profile-create NAME=pc2)" >&2
    exit 1
  fi
  if [[ ! "$NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    echo "Invalid profile name '$NAME' (use a-z, 0-9, _, -; start with letter or digit)" >&2
    exit 1
  fi
  for reserved in $RESERVED_PROFILES; do
    if [[ "$NAME" == "$reserved" ]]; then
      echo "Profile name '$NAME' is reserved (use a different name)" >&2
      exit 1
    fi
  done
}

detect_dev_host() {
  if [[ -n "${DEV_HOST:-}" ]]; then
    echo "$DEV_HOST"
    return
  fi
  local ip
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [[ -n "$ip" ]]; then
    echo "$ip"
  else
    echo "127.0.0.1"
  fi
}

parse_profile_var() {
  local file="$1" var="$2"
  local raw
  raw="$(grep "^${var}[[:space:]]" "$file" | head -1 | sed -E "s/^${var}[[:space:]]*\\?=[[:space:]]*//")"
  raw="${raw//\$(HOME)/$HOME}"
  echo "$raw"
}

max_profile_port() {
  local var="$1" default="$2" step="$3"
  local max="$default"
  local val
  for f in profiles/*.env; do
    [[ -f "$f" ]] || continue
    val="$(parse_profile_var "$f" "$var" 2>/dev/null || true)"
    if [[ "$val" =~ ^[0-9]+$ ]] && (( val > max )); then
      max="$val"
    fi
  done
  echo $((max + step))
}

profile_file() {
  echo "profiles/${NAME}.env"
}

action_create() {
  validate_name
  local pf
  pf="$(profile_file)"
  if [[ -f "$pf" ]]; then
    echo "Profile already exists: $pf" >&2
    exit 1
  fi

  local dev_host host_port relay_port
  dev_host="$(detect_dev_host)"
  host_port="${PROFILE_HOST_PORT:-$(max_profile_port HOST_PORT 3019 10)}"
  relay_port="${PROFILE_RELAY_HOST_PORT:-$(max_profile_port RELAY_HOST_PORT 7777 1)}"

  cat >"$pf" <<EOF
# Profile: ${NAME} (auto-generated disposable stack)
#
# Created by: make profile-create NAME=${NAME}
# Destroy with: make profile-destroy NAME=${NAME} YES=1

CONFIG_DIR           ?= \$(HOME)/.nsecbunker-config-${NAME}
PROJECT              ?= nsecbunker-${NAME}
HOST_PORT            ?= ${host_port}
KEY_NAME             ?= ${NAME}@local
DEV_HOST             ?= ${dev_host}
RELAY                ?= ws://relay:8080
CLIENT_RELAY         ?= ws://${dev_host}:${relay_port}
PUBLIC_BASE_URL      ?= http://${dev_host}:${host_port}
RELAY_SMOKE_URL      ?= ws://relay:8080
SIGNER_IDENTITY_FILE ?= signer-identity-${NAME}.txt
LOCAL_RELAY          ?= 1
RELAY_HOST_PORT      ?= ${relay_port}
ADMIN_NPUBS          ?=
EOF

  echo "==> created $pf"
  echo "    CONFIG_DIR=~/.nsecbunker-config-${NAME}"
  echo "    HOST_PORT=${host_port}  RELAY_HOST_PORT=${relay_port}"
  echo "    DEV_HOST=${dev_host}"
  echo "==> next: make profile-setup NAME=${NAME}"
}

run_keygen() {
  local output
  output="$(make keygen PROFILE="$NAME" KEYGEN="${KEYGEN:-generic}" 2>&1)"
  echo "$output"
  NSEC="$(printf '%s\n' "$output" | sed -n 's/^nsec=//p')"
  NPUB="$(printf '%s\n' "$output" | sed -n 's/^npub=//p')"
  if [[ -z "$NSEC" ]]; then
    echo "keygen failed: no nsec in output" >&2
    exit 1
  fi
}

resolve_admin_npub() {
  if [[ -n "${ADMIN_NPUBS:-}" ]]; then
    return
  fi
  if [[ -f .env ]] && grep -q '^ADMIN_NPUBS=' .env; then
    ADMIN_NPUBS="$(grep '^ADMIN_NPUBS=' .env | cut -d= -f2- | tr -d '"')"
  fi
  if [[ -z "${ADMIN_NPUBS:-}" ]]; then
    read -r -p "Admin npub (npub1...): " ADMIN_NPUBS
  fi
}

action_setup() {
  validate_name
  local pf
  pf="$(profile_file)"
  if [[ ! -f "$pf" ]]; then
    echo "==> profile $NAME not found; creating it first"
    action_create
  fi

  resolve_admin_npub

  if [[ -z "${PASSPHRASE:-}" ]]; then
    PASSPHRASE="$(openssl rand -base64 24)"
  fi
  if [[ -z "${WEB_AUTH_PASSWORD:-}" ]]; then
    WEB_AUTH_PASSWORD="$(openssl rand -base64 16)"
  fi

  echo "==> generating signing identity for profile $NAME"
  run_keygen
  echo "==> SAVE THIS nsec (shown once): $NSEC"
  echo "==> signer npub: $NPUB"

  export NSEC PASSPHRASE WEB_AUTH_PASSWORD ADMIN_NPUBS
  # Sub-make must not inherit the parent make's default-profile exports.
  env -u SIGNER_IDENTITY_FILE -u NSECBUNKER_CONFIG_DIR -u COMPOSE_PROJECT_NAME \
    -u NSECBUNKER_HOST_PORT -u NSECBUNKER_KEY_NAME -u RELAY_HOST_PORT -u COMPOSE_PROFILES \
    -u DEV_HOST -u CLIENT_RELAY -u PUBLIC_BASE_URL -u RELAY \
    make build PROFILE="$NAME"
  env -u SIGNER_IDENTITY_FILE -u NSECBUNKER_CONFIG_DIR -u COMPOSE_PROJECT_NAME \
    -u NSECBUNKER_HOST_PORT -u NSECBUNKER_KEY_NAME -u RELAY_HOST_PORT -u COMPOSE_PROFILES \
    -u DEV_HOST -u CLIENT_RELAY -u PUBLIC_BASE_URL -u RELAY \
    make setup PROFILE="$NAME"

  echo ""
  echo "==> profile $NAME is ready"
  echo "    make connection PROFILE=$NAME"
  echo "    make profile-destroy NAME=$NAME YES=1   # remove when done"
}

load_profile_env() {
  local pf
  pf="$(profile_file)"
  [[ -f "$pf" ]] || { echo "Profile not found: $NAME" >&2; exit 1; }

  export NSECBUNKER_CONFIG_DIR="$(parse_profile_var "$pf" CONFIG_DIR)"
  export NSECBUNKER_HOST_PORT="$(parse_profile_var "$pf" HOST_PORT)"
  export COMPOSE_PROJECT_NAME="$(parse_profile_var "$pf" PROJECT)"
  export SIGNER_IDENTITY_FILE="$(parse_profile_var "$pf" SIGNER_IDENTITY_FILE)"
  export RELAY_HOST_PORT="$(parse_profile_var "$pf" RELAY_HOST_PORT)"

  local local_relay
  local_relay="$(parse_profile_var "$pf" LOCAL_RELAY)"
  if [[ "$local_relay" == "1" ]]; then
    export COMPOSE_PROFILES=local
  else
    unset COMPOSE_PROFILES || true
  fi
}

action_destroy() {
  validate_name
  local pf config_dir signer_file
  pf="$(profile_file)"
  if [[ ! -f "$pf" ]]; then
    echo "Profile not found: $NAME" >&2
    exit 1
  fi

  load_profile_env
  config_dir="$NSECBUNKER_CONFIG_DIR"
  signer_file="$SIGNER_IDENTITY_FILE"

  echo "==> stopping stack (project=$COMPOSE_PROJECT_NAME)"
  docker compose down -v 2>/dev/null || true

  remove_all() {
    if [[ -d "$config_dir" ]]; then
      chown -R "$(id -u):$(id -g)" "$config_dir" 2>/dev/null || true
      rm -rf "$config_dir"
      echo "==> removed $config_dir"
    fi
    if [[ -f "$signer_file" ]]; then
      rm -f "$signer_file"
      echo "==> removed $signer_file"
    fi
    if [[ -f "$pf" ]]; then
      rm -f "$pf"
      echo "==> removed $pf"
    fi
  }

  if [[ "${YES:-}" == "1" ]]; then
    remove_all
    echo "==> profile $NAME destroyed"
    return
  fi

  read -r -p "Remove config dir $config_dir? [y/N] " ans
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    rm -rf "$config_dir" && echo "==> removed $config_dir"
  fi
  read -r -p "Remove signer file $signer_file? [y/N] " ans
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    rm -f "$signer_file" && echo "==> removed $signer_file"
  fi
  read -r -p "Remove profile file $pf? [y/N] " ans
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
    rm -f "$pf" && echo "==> removed $pf"
  fi
  echo "==> profile $NAME teardown complete"
}

case "$ACTION" in
  create) action_create ;;
  setup) action_setup ;;
  destroy) action_destroy ;;
  *) usage ;;
esac
