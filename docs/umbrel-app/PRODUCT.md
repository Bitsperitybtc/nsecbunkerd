# Bitspark Signer

What this app is. Constraints: [CONTRACT.md](./CONTRACT.md). How to build it: [ARCHITECTURE.md](./ARCHITECTURE.md). Line of thought: [SIGNER-STRATEGY.md](./SIGNER-STRATEGY.md).

An Umbrel app that holds one Nostr identity and signs for Bitspark over **NIP-46**, so the Bitspark SPA never holds a long-lived `nsec`.

Happy path: install this app and Bitspark on the same node, open Bitspark, pick **Bitspark Signer**, approve once.

Public Bitspark uses the same app and the same protocol when a relay both the browser and the node can reach is configured. Amber, nsec.app, and other NIP-46 signers stay available in Bitspark as other sign-in choices.

This app is not a wallet and not a hosted bunker.
