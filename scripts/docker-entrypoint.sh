#!/bin/sh
# Non-interactive start: passphrase from Docker secret (same format as signer-identity.txt).
# When started as root, chown the config volume to DOCKER_UID then drop privileges.
set -eu

start_nsecbunkerd() {
  KEY_NAME="${NSECBUNKER_KEY_NAME:-bitspark@local}"
  SECRET_FILE="${SIGNER_SECRET_FILE:-/run/secrets/signer_identity}"
  PASS="$(sed -n 's/^encryption_passphrase=//p' "$SECRET_FILE" | tr -d '\r')"
  if [ -z "$PASS" ]; then
    echo "Missing encryption_passphrase= line in $SECRET_FILE" >&2
    exit 1
  fi
  printf '%s\n' "$PASS" | exec node ./dist/index.js start --verbose --key "$KEY_NAME"
}

drop_privileges() {
  if [ "$(id -u)" = "0" ] && [ -n "${DOCKER_UID:-}" ]; then
    chown -R "${DOCKER_UID}:${DOCKER_GID:-${DOCKER_UID}}" /app/config 2>/dev/null || true
    exec setpriv --reuid="${DOCKER_UID}" --regid="${DOCKER_GID:-${DOCKER_UID}}" --init-groups \
      /bin/sh "$0" --as-user
  fi
}

drop_privileges

if [ "${1:-}" = "--as-user" ]; then
  shift
fi

start_nsecbunkerd
