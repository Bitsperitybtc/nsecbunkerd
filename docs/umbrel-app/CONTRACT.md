# Bitspark Signer — contract

Frozen constraints. Product: [PRODUCT.md](./PRODUCT.md). Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md). Line of thought: [SIGNER-STRATEGY.md](./SIGNER-STRATEGY.md). How we decide: [signer-product-decisions.md](../workflows/signer-product-decisions.md). Freeze from notes: [freeze-product-contract.md](../workflows/freeze-product-contract.md).

## Job

- Enable Umbrel users to use Bitspark without assembling a third-party signer.
- Same signer must work for public Bitspark (browser not on the node) without a second protocol.
- Other NIP-46 signers remain fallbacks in Bitspark, not the enablement path.

## Protocol

One path everywhere: NIP-46 over a relay mailbox. This app implements `connect`, `get_public_key`, `sign_event` (including kind 13), `nip44_encrypt` / `nip44_decrypt`, `ping`. Identity is not Lightning (NWC stays a separate Bitspark concern).

Local vs public is **which relay URL** (and whether Bitspark already knows it), not a different auth mechanism.

- **Same node:** mailbox is the local relay. Umbrel injects enough for the tab to form the **browser-facing** mailbox URL (static sites cannot read Docker env; the Bitspark app ships a small config the tab can load). Bitspark uses that mailbox for NIP-46: `nostrconnect` (listen, then hand the URI to the signer) or `bunker://` (`connect` request). The signer is already watching that relay.
- **Public Bitspark / other signers:** same protocol / Approve; the mailbox is whatever relay both sides can open (user-configured or the existing remote-signer default).

Optional local convenience (not a second protocol): if config also has the **signer UI URL**, Bitspark may open that page so Approve is a popup/tab. On public Bitspark that URL is not `localhost` on the visitor’s laptop, so no auto-popup unless the user has a reachable signer UI. If the popup is blocked, the user pastes the `nostrconnect://` URI into this app’s UI — Approve still happens there. The signer does not see a pending relay event until that URI is delivered (`bunker://` is the flow where the client publishes `connect` first).

Relay config stays two fields: URL the **signer process** dials (often Docker-internal) vs URL the **browser** uses (localhost / node name / public `wss`). They may be equal.

## Must

- New implementation in a **new repo**. `nsecbunkerd` is reference and interop target only; do not wrap or migrate its admin/product.
- Create or import one `nsec`; encrypt at rest; show backup once.
- Separate mailbox key internally; **one identity** in the UI (no two connection strings).
- Pairing: `nostrconnect` first; `bunker://` fallback.
- Approve / deny / revoke **clients** in this app’s UI (not `app.nsecbunker.com`, not a Prisma `User` for `/requests`).
- Default mailbox: local relay on the node (Mode A).
- Relay config is two fields from day one: URL the **signer** dials vs URL the **browser** is told to use (they may be equal).
- User can add a reachable/public relay so public Bitspark can share the mailbox (Mode B). We do not operate a public relay for this.
- Bitspark: “Bitspark Signer” sign-in uses the injected mailbox (and optional signer UI URL) and the same NIP-46 pairing as other remote signers. Existing remote-signer and bunker-URI paths stay.

## Must not

- Long-lived `nsec` in the Bitspark SPA.
- Bitspark-only HTTP signing API.
- Drop support for other NIP-46 signers in Bitspark.
- Mix Lightning / LNBits / NWC into this app.
- Require `app.nsecbunker.com`, hosted admin RPC, `create_account`, username@domain web-auth, NIP-05 hosting, or policy-token engines.
- Make local-relay-only the architecture (local is the default, not a lock-in).
- Treat QR as the Umbrel happy path (the node has no camera).

## Defaults (v1)

| Topic | Default |
| --- | --- |
| Same-node pairing | Local relay as mailbox; optional open signer UI for Approve |
| Public Bitspark | Copy-link / pending approval **only if** a relay both sides can open is configured |
| QR | Not v1. Later, optional: laptop shows a **LAN URL** so a phone on the same network opens the signer UI. Phone is a remote control, not a second signer |
| Notifications | Signer process subscribed to the mailbox. Not phone push. App stopped → no prompt |
| Multi-identity | Not v1. Data model: one key, many approved clients (revoke required) |
| Hosted keys (old “Mode C”) | **Out.** Other providers exist. Revisit only as a new product decision |

## Repos

- **Product / contract / notes:** this tree (`docs/umbrel-app/`).
- **Signer code:** new git root in the workspace; do not implement inside `nsecbunkerd`.
- **Bitspark:** sign-in option + Umbrel config wiring; protocol stays NIP-46.
