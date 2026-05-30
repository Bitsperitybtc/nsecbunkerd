#!/bin/sh
# Generate a signing identity inside the container.
#
#   KEYGEN=generic  (default) -> Node built-in crypto + generic bech32, no nostr-tools
#   KEYGEN=nostr              -> nostr-tools (generateSecretKey/getPublicKey)
#
# Prints:
#   nsec=...
#   npub=...
#   pubkey_hex=...
set -eu

KEYGEN="${KEYGEN:-generic}"

if [ "$KEYGEN" = "nostr" ]; then
  exec node --input-type=module -e "import { generateSecretKey, getPublicKey, nip19 } from 'nostr-tools'; const sk = generateSecretKey(); const pk = getPublicKey(sk); console.log('nsec=' + nip19.nsecEncode(sk)); console.log('npub=' + nip19.npubEncode(pk)); console.log('pubkey_hex=' + pk);"
fi

exec node /app/scripts/keygen.mjs
