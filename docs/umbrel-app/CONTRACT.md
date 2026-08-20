# Bitspark Signer — contract

Frozen constraints. Product: [PRODUCT.md](./PRODUCT.md). Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md). Line of thought: [SIGNER-STRATEGY.md](./SIGNER-STRATEGY.md). How we decide: [signer-product-decisions.md](../workflows/signer-product-decisions.md). Freeze from notes: [freeze-product-contract.md](../workflows/freeze-product-contract.md).

## Jobs

Two bars. The product does not redefine the base.

- **Signer (base):** this process is a complete NIP-46 remote signer. Hold one encrypted identity, speak NIP-46 over a mailbox, approve / deny / revoke clients in this UI. Any compliant client can pair without Bitspark or Umbrel.
- **Bitspark Signer (product):** enable Umbrel users to use Bitspark without assembling a third-party signer. The same signer must work for public Bitspark (browser not on the node) without a second protocol. Other NIP-46 signers remain fallbacks in Bitspark, not the enablement path.

## Protocol

One path everywhere: NIP-46 over a relay mailbox. This app implements `connect`, `get_public_key`, `sign_event` (including kind 13), `nip44_encrypt` / `nip44_decrypt`, `ping`. Identity is not Lightning (NWC stays a separate Bitspark concern).

Local vs public is **which relay URL** (and whether a client already knows it), not a different auth mechanism.

- **Same node:** mailbox is the local relay. The signer already watches it. A client that knows the **browser-facing** mailbox URL (injected into Umbrel Bitspark; pasted or typed otherwise) uses NIP-46: `nostrconnect` (listen, then hand the URI to the signer) or `bunker://` (`connect` request).
- **Public Bitspark / other clients:** same protocol / Approve; the mailbox is whatever relay both sides can open (user-configured or the existing remote-signer default).

Optional product convenience (not a second protocol): if Umbrel Bitspark also has the **signer UI URL**, it may open that page so Approve is a popup/tab. On public Bitspark that URL is not `localhost` on the visitor’s laptop, so no auto-popup unless the user has a reachable signer UI. If the popup is blocked, the user pastes the `nostrconnect://` URI into this app’s UI — Approve still happens there. The signer does not see a pending relay event until that URI is delivered (`bunker://` is the flow where the client publishes `connect` first).

Relay config stays two fields: URL the **signer process** dials (often Docker-internal) vs URL the **browser** uses (localhost / node name / public `wss`). They may be equal.

## Must — signer (base)

- New implementation in a **new repo**. `nsecbunkerd` is reference and interop target only; do not wrap or migrate its admin/product.
- Create or import one `nsec` in this UI only; encrypt at rest (**NIP-49**); show backup once on generate. Never put `nsec` in env or compose. Unlock after reboot is **not frozen** — working assumption and alternative: [ARCHITECTURE.md](./ARCHITECTURE.md) §6.
- Env seeds first boot (data dir, listen, default mailbox dial, log level). After that, UI-persisted `state.json` is source of truth.
- Separate mailbox key internally; **one identity** in the UI (no two connection strings).
- Pairing: `nostrconnect` first; `bunker://` fallback.
- Approve / deny / revoke **clients** in this app’s UI (not `app.nsecbunker.com`, not a Prisma `User` for `/requests`).
- Default mailbox: local relay on the node.
- Relay config is two fields from day one: URL the **signer** dials vs URL the **browser** is told to use (they may be equal).
- User can add a reachable/public relay so a browser not on the node can share the mailbox. We do not operate a public relay for this.
- Prove the signer with a generic NIP-46 client (NDK in tests) before Bitspark wiring.

## Must — product (Bitspark Signer)

- Bitspark: “Bitspark Signer” sign-in uses the injected mailbox (and optional signer UI URL) and the same NIP-46 pairing as other remote signers. Existing remote-signer and bunker-URI paths stay.
- Umbrel writes a small JSON the Bitspark tab can fetch so it can form the browser-facing mailbox URL (static sites cannot read Docker env). Independent install still works via paste.
- Umbrel packaging is last. The signer compose must already work without `app_proxy` or Bitspark.

## Must not

**Signer**

- Bitspark-only HTTP signing API.
- Mix Lightning / LNBits / NWC into this app.
- Require `app.nsecbunker.com`, hosted admin RPC, `create_account`, username@domain web-auth, NIP-05 hosting, or policy-token engines.
- Make local-relay-only the architecture (local is the default, not a lock-in).
- Treat the daemon as incomplete until Bitspark is wired.
- Put `nsec` in env, compose, or Docker secrets.

**Product**

- Long-lived `nsec` in the Bitspark SPA.
- Drop support for other NIP-46 signers in Bitspark.
- Treat QR as the Umbrel happy path (the node has no camera).

## Defaults (v1)

| Topic | Default | Layer |
| --- | --- | --- |
| Same-node pairing | Local relay as mailbox; optional open signer UI for Approve | product |
| Public Bitspark | Copy-link / pending approval **only if** a relay both sides can open is configured | product |
| QR | Not v1. Later, optional: laptop shows a **LAN URL** so a phone on the same network opens the signer UI. Phone is a remote control, not a second signer | product |
| Notifications | Signer process subscribed to the mailbox. Not phone push. App stopped → no prompt | signer |
| Unlock after reboot | **Not frozen.** Working assumption: auto-unlock so quiet signing survives reboot. Alternative: user passphrase (real encryption; signing needs a UI unlock after every restart). Details in ARCHITECTURE §6 | signer |
| Multi-identity | Not v1. Data model: one key, many approved clients (revoke required) | signer |
| Hosted keys (old “Mode C”) | **Out.** Other providers exist. Revisit only as a new product decision | product |

## Repos

- **Product / contract / notes:** this tree (`docs/umbrel-app/`).
- **Signer code:** new git root in the workspace; do not implement inside `nsecbunkerd`.
- **Bitspark:** sign-in option + Umbrel config wiring; protocol stays NIP-46.
