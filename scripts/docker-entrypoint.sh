#!/bin/sh
# Non-interactive start: passphrase from Docker secret (same format as nsecbunkerd-local/signer-identity.txt).
set -eu
KEY_NAME="${NSECBUNKER_KEY_NAME:-bitspark@local}"
SECRET_FILE="${SIGNER_SECRET_FILE:-/run/secrets/signer_identity}"
PASS="$(sed -n 's/^encryption_passphrase=//p' "$SECRET_FILE" | tr -d '\r')"
if [ -z "$PASS" ]; then
  echo "Missing encryption_passphrase= line in $SECRET_FILE" >&2
  exit 1
fi
printf '%s\n' "$PASS" | exec node ./dist/index.js start --verbose --key "$KEY_NAME"
