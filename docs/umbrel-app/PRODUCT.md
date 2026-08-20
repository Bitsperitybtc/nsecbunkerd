# Bitspark Signer

What this app is. Constraints: [CONTRACT.md](./CONTRACT.md). How to build it: [ARCHITECTURE.md](./ARCHITECTURE.md). Line of thought: [SIGNER-STRATEGY.md](./SIGNER-STRATEGY.md).

**Bitspark Signer** is the Umbrel product: a NIP-46 remote signer, packaged and wired so the Bitspark SPA never holds a long-lived `nsec`.

Under that name is a complete **signer** — one identity, client ACL, mailbox, Approve in this UI. It works with any NIP-46 client. Bitspark is the first client we wire, not the definition of the signer.

Happy path: install this app and Bitspark on the same node, open Bitspark, pick **Bitspark Signer**, approve once.

Public Bitspark uses the same signer and the same protocol when a relay both the browser and the node can reach is configured. Amber, nsec.app, and other NIP-46 signers stay available in Bitspark as other sign-in choices.

This app is not a wallet and not a hosted bunker.
