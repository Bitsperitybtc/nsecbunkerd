#!/bin/sh
# Run prisma migrations as the host user; fix bind-mount ownership when started as root.
set -eu

run_migrate() {
  exec npx prisma migrate deploy
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

run_migrate
