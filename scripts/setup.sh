#!/usr/bin/env bash
# Orchestrate a full nsecBunker setup. Intended to be invoked via `make setup`,
# which exports the profile env (NSECBUNKER_CONFIG_DIR, NSECBUNKER_HOST_PORT,
# COMPOSE_PROJECT_NAME) and passes KEY_NAME / RELAY / ADMIN_NPUBS.
#
# Secrets are read from the environment if present, otherwise prompted:
#   PASSPHRASE          encryption passphrase for the signing nsec
#   NSEC                the signing identity nsec (nsec1...)
#   WEB_AUTH_PASSWORD   password for the browser approval page
#
# The script is idempotent: re-running skips the key import if it already exists.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG_DIR="${NSECBUNKER_CONFIG_DIR:?NSECBUNKER_CONFIG_DIR not set (use make)}"
HOST_PORT="${NSECBUNKER_HOST_PORT:-3009}"
KEY_NAME="${KEY_NAME:-bitspark@local}"
RELAY="${RELAY:-wss://nos.lol}"

CONFIG_JSON="$CONFIG_DIR/nsecbunker.json"
SIGNER_FILE="signer-identity.txt"

echo "==> nsecBunker setup (project=${COMPOSE_PROJECT_NAME:-nsecbunker} dir=$CONFIG_DIR port=$HOST_PORT key=$KEY_NAME)"
mkdir -p "$CONFIG_DIR"

# --- 1. .env ---------------------------------------------------------------
if [ ! -f .env ]; then
  cp .env.example .env
  echo "==> created .env from .env.example"
fi

set_env() {
  local key="$1" val="$2"
  if grep -q "^${key}=" .env; then
    sed -i "s|^${key}=.*|${key}=${val}|" .env
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}

set_env NSECBUNKER_KEY_NAME "$KEY_NAME"

if [ -n "${ADMIN_NPUBS:-}" ]; then
  set_env ADMIN_NPUBS "$ADMIN_NPUBS"
elif ! grep -q "^ADMIN_NPUBS=" .env; then
  read -r -p "Admin npub (npub1...): " ADMIN_NPUBS
  set_env ADMIN_NPUBS "$ADMIN_NPUBS"
fi

# --- 2. signer-identity.txt (passphrase-only secret) -----------------------
if [ -f "$SIGNER_FILE" ] && grep -q '^encryption_passphrase=' "$SIGNER_FILE"; then
  PASSPHRASE="$(sed -n 's/^encryption_passphrase=//p' "$SIGNER_FILE" | tr -d '\r')"
  echo "==> using existing $SIGNER_FILE"
else
  if [ -z "${PASSPHRASE:-}" ]; then
    read -r -s -p "Choose an encryption passphrase: " PASSPHRASE; echo
  fi
  ( umask 077; printf '# nsecbunkerd signer secret - DO NOT COMMIT\nencryption_passphrase=%s\n' "$PASSPHRASE" > "$SIGNER_FILE" )
  echo "==> wrote $SIGNER_FILE"
fi

# --- 3. Import signing key (idempotent) ------------------------------------
if [ -f "$CONFIG_JSON" ] && grep -Fq "\"$KEY_NAME\"" "$CONFIG_JSON"; then
  echo "==> key '$KEY_NAME' already present; skipping import"
else
  if [ -z "${NSEC:-}" ]; then
    read -r -s -p "Paste the signing nsec for $KEY_NAME (nsec1...): " NSEC; echo
  fi
  echo "==> importing signing key (creates nsecbunker.json with generated admin key)"
  printf '%s\n%s\n' "$PASSPHRASE" "$NSEC" | \
    docker compose run --rm -T --no-deps --entrypoint "" nsecbunkerd \
      node ./dist/index.js add --config /app/config/nsecbunker.json --name "$KEY_NAME"
fi

# --- 4. Patch relays + web auth into nsecbunker.json -----------------------
echo "==> applying relay + web-auth settings"
docker compose run --rm -T --no-deps --entrypoint "" \
  -e NSECBUNKER_RELAY="$RELAY" -e NSECBUNKER_HOST_PORT="$HOST_PORT" \
  nsecbunkerd node /app/scripts/patch-config.mjs

# --- 5. Start --------------------------------------------------------------
echo "==> starting stack"
docker compose up -d

# --- 6. Wait for connection.txt -------------------------------------------
printf '==> waiting for connection.txt'
for _ in $(seq 1 60); do
  if docker compose exec -T nsecbunkerd test -f /app/config/connection.txt 2>/dev/null; then
    printf ' ok\n'; break
  fi
  printf '.'; sleep 1
done

# --- 7. Web auth user ------------------------------------------------------
if [ -z "${WEB_AUTH_PASSWORD:-}" ]; then
  read -r -s -p "Choose a web auth password: " WEB_AUTH_PASSWORD; echo
fi
echo "==> creating web auth user"
docker compose exec -T -e WEB_AUTH_PASSWORD="$WEB_AUTH_PASSWORD" nsecbunkerd \
  node /app/scripts/create-web-auth-user.mjs

# --- 8. Show connection strings -------------------------------------------
echo "==> setup complete. connection strings:"
echo "--- connection.txt (signing clients) ---"
docker compose exec -T nsecbunkerd cat /app/config/connection.txt; echo
echo "--- admin-connection.txt (admin UI) ---"
docker compose exec -T nsecbunkerd cat /app/config/admin-connection.txt; echo
echo "==> browser approvals: http://localhost:$HOST_PORT/requests/<request-id>"
