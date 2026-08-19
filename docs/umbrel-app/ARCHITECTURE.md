# Bitspark Signer — architecture

Status: **ready to implement.** **Product:** [PRODUCT.md](./PRODUCT.md). **Contract:** [CONTRACT.md](./CONTRACT.md). **Line of thought:** [SIGNER-STRATEGY.md](./SIGNER-STRATEGY.md).

This is the build map: components, data, pairing, packaging. It does not reopen NIP-46 vs HTTP, wrap-vs-new, or hosted keys.

## 1. What we are building

A **new** small NIP-46 remote signer (new git root). It holds one Nostr identity, approves clients in its own UI, and signs for Bitspark (and any other NIP-46 client) over a relay mailbox.

v1 is two Umbrel apps: **Bitspark Signer** (this, including a local mailbox relay) and **Bitspark** (existing SPA). Same protocol as Amber / nsec.app. nsecbunkerd is reference and interop target only.

```text
  Bitspark tab                    Mailbox                     Signer
  (throwaway                      (kind 24133,                user nsec + mailbox key
   client key)                    NIP-44 RPC)                 + client ACL + UI

  nostrconnect://  ──out of band──►  UI Approve
  kind 24133       ◄──── relay ────►  daemon

  Mailbox = bundled nostr-rs-relay (local default) and/or a user-configured wss://
```

Signing never uses HTTP. The signer’s HTTP port is only: local UI, setup, approve/deny/revoke, relay settings.

## 2. Contradictions resolved

Taken from PRODUCT / CONTRACT / STRATEGY / current NIP-46 / Bitspark’s client. CONTRACT wins on product scope; NIP-46 wins on wire format; Bitspark’s existing client wins on methods and `connect` param order.

| Tension | Resolution |
| --- | --- |
| Strategy sketches Mode C; CONTRACT parks hosted keys | **Out of v1 and not a design driver.** v1 still uses *identity + client ACL* because revoke and several Bitspark tabs need it — not because we plan to host keys. |
| Strategy Mode B mentions QR; CONTRACT forbids QR as Umbrel happy path | **No QR in v1.** Mode A: inject mailbox + optional open of signer UI. Mode B: copy `nostrconnect://`. Phone-as-remote-control is later. |
| Strategy “same-node discovery”; CONTRACT is config injection | **No mDNS / custom discovery.** Umbrel writes a small JSON the Bitspark tab can fetch. Independent install still works via paste. |
| `auth_url` in NIP-46 and nsecbunkerd; CONTRACT wants in-app Approve | **Do not send `auth_url` in v1.** Pending requests live in this app’s UI. Bitspark already waits on the relay; its `authUrl` handler simply stays idle. |
| Strategy “new app or module in this repo”; CONTRACT “new repo” | **New git root** (working name `bitspark-signer`). This folder stays the product/contract/architecture home until that repo exists. |
| Separate mailbox key vs “one identity” | **Two keys in storage, one npub in the UI.** `bunker://` uses the mailbox pubkey; `get_public_key` returns the user pubkey. Users never see a second connection string. |
| Bitspark still requests `nip04_*`; CONTRACT names NIP-44 | **Implement both.** Product flows are NIP-44 / kind 13. `nip04_*` exists so Bitspark’s `connect` perm list and NDK do not fail. |
| Auto-start vs encrypt-at-rest | **NIP-49 on disk; auto-unlock from the app volume** so quiet signing survives container restart. Disk access to the node is the trust boundary (honest Umbrel model). No passphrase prompt every boot in v1. |
| Local relay vs public Bitspark | **Bundled local relay is the Mode A default mailbox, not the only mailbox.** User can add a `wss://` relay both the home signer and a public Bitspark tab can open. We do not operate a public relay. |
| CONTRACT “inject browser-facing URL” vs ports-only JSON | **Same outcome.** Config ships mailbox/UI **ports**; the tab builds `ws://${location.hostname}:…` so Docker-internal names never leak. That *is* the browser-facing URL. |
| CONTRACT / freeze “publishes `connect`” vs NIP-46 `nostrconnect://` | **Happy path is client-initiated.** Bitspark **listens** and hands the URI out of band; the signer publishes the connect **response**. `bunker://` is the flow where the client publishes `connect` first. CONTRACT protocol section now matches this. |

No remaining contradiction that blocks a first implementation.

## 3. Deployment (same binary)

### Mode A — Umbrel Bitspark + Umbrel signer (primary)

1. Install signer (creates or imports one identity, backup shown once).
2. Install Bitspark (independent; no hard Umbrel `dependencies:` on the signer).
3. Open Bitspark → **Bitspark Signer** (only if injected config is present) → optional popup/tab of signer UI → Approve once.
4. Further `sign_event` / NIP-44 from that client pubkey are quiet.

Mailbox = local relay in the signer compose. Browser-facing URL is injected; signer-facing URL is the Docker DNS name.

### Mode B — Public Bitspark + user-run signer

Same daemon and UI. User adds a reachable `wss://` mailbox in signer settings and uses that same URL in Bitspark’s Nostr Connect relay field (or a future “Bitspark Signer” path that still asks for the mailbox). Copy-link `nostrconnect://`, approve in the Umbrel signer UI. No `localhost` `auth_url`.

### Dev / test — same binary, no Umbrel

Umbrel is **packaging** (`app_proxy`, one advertised UI port, volume paths). It is not required to develop or to prove NIP-46.

Daily loop is Docker Compose in the new repo: the same two services as the Umbrel app (`signer` + `relay`), without `app_proxy`.

| Role | Dev (laptop) | Umbrel |
| --- | --- | --- |
| Signer UI | `http://127.0.0.1:8740` (no Umbrel login) | `http://<node>:8740` behind `app_proxy` |
| Mailbox (browser + host-run daemon) | `ws://127.0.0.1:8741` | `ws://<node>:8741` |
| Mailbox (daemon in Compose) | `ws://relay:8080` | `ws://relay:8080` |
| Bitspark | `npm run dev` / `npm run preview` | Bitspark app |

The two relay URL fields **may be equal** on a laptop (both `ws://127.0.0.1:8741` if the daemon runs on the host). Compose-internal vs published port is the same split as production.

**Local relay:** yes — it is a first-class sidecar of **this** signer app (`nostr-rs-relay`, kind `24133` allowlist, host port 8741). It is not a third Umbrel app, not Umbrel’s “Nostr Relay” store app, and not nsecbunkerd’s `PROFILE=local` stack. That NSEC-1 work is the pattern to copy, not a runtime dependency.

How to exercise Mode A without Umbrel:

1. `docker compose up` in `bitspark-signer` (relay + signer). Fast UI iteration: compose **only the relay**, run the daemon with `npm run dev` on the host, set `signerDial` = `ws://127.0.0.1:8741`.
2. Bitspark `npm run dev -- --host 0.0.0.0`.
3. Pair: either existing **Use a remote signer** with relay `ws://127.0.0.1:8741`, or (once wired) the same `signer-config.json` as Umbrel so the tab builds `ws://localhost:8741` / `http://localhost:8740` from `location.hostname`. Local Vite: gitignored or `import.meta.env.DEV` only — **do not commit that file into `static/`** or the public production build will show “Bitspark Signer” against the wrong host.
4. Approve in `http://127.0.0.1:8740`. Then sign a kind `0` and a kind `13` from Bitspark.

Mode B without Umbrel: same signer, add a public `wss://` mailbox in signer settings, open Bitspark via `npm run preview` (or another origin) and put that `wss://` in the Nostr Connect relay field. Copy-link, approve in the local signer UI.

**Tests (no Umbrel, no Bitspark UI required for the first two):**

| Layer | What | Where |
| --- | --- | --- |
| Unit | URI parse, `connect` param order, ACL, NIP-49, kind-13 grant | `bitspark-signer` `npm test` |
| Mailbox smoke | publish/read kind 24133 on `ws://127.0.0.1:8741` | compose `relay` + a few lines of `nostr-tools` (same idea as nsecbunkerd `relay-smoke`) |
| Interop | NDK `nostrconnect` + `bunker://` against the daemon | `bitspark-signer` tests using `@nostr-dev-kit/ndk` as **client** |
| Manual A | Bitspark `npm run dev` + local compose | laptop |
| Manual B | Bitspark preview + `wss://` mailbox | laptop; signer still local |
| Umbrel last | `app_proxy`, extra host port, injected JSON mount | only when packaging |

Do not wait for an Umbrel node to start implementation. Do not stand up nsecbunkerd as the dev signer.

### Not v1

- Hosted keys we operate (old Mode C).
- QR, phone push, NIP-89/NIP-05 discovery, multi-identity, Lightning/NWC, wrapping nsecbunkerd.

## 4. Components

Two containers in the signer app, one SPA elsewhere:

| Piece | Where | Role |
| --- | --- | --- |
| **Daemon** | new repo, one Node process | Holds keys in memory after unlock; NIP-46 over relays; client ACL; serves UI + local control HTTP |
| **UI** | static pages from that process | First-run, backup, pending Approve, clients, relay settings, copy `bunker://` |
| **Mailbox relay** | `nostr-rs-relay` sidecar (same pattern as NSEC-1 and Umbrel’s Nostr Relay app) | Default **NIP-46 mailbox** for Mode A, not a general personal relay. Set `event_kind_allowlist = [24133]`. Other NIP-46 clients can use it; Damus-style kind `1` backup does not belong here (marketplace relays stay Bitspark’s). Kind `24133` is ephemeral (2xxxx): pairing needs Bitspark **already subscribed** before Approve. |
| **Bitspark SPA** | `bitspark_btc` | Existing NIP-46 client (`nip46Bunker.ts`). Umbrel package **bind-mounts** static `signer-config.json`. Public site unchanged except it keeps Amber/bunker/NIP-07 |

Do not add a third Umbrel app for the relay. Do not implement a custom relay in the daemon.

### Why the mailbox is not the UI port

Umbrel `app_proxy` authenticates HTTP **and WebSocket upgrades**. Bitspark’s tab is a different origin and will not reliably present the signer’s Umbrel cookie. Official Umbrel Nostr Relay therefore exposes `ws://umbrel.local:4848` without that login.

v1: **UI on the app’s main port (Umbrel-authed). Mailbox on a dedicated published WebSocket port (no Umbrel cookie).** NIP-46 is the access control. Do not put the mailbox behind Umbrel login.

## 5. Protocol (wire)

Follow [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md) as Bitspark already speaks it via NDK.

**Methods (must):** `connect`, `get_public_key`, `ping`, `sign_event`, `nip44_encrypt`, `nip44_decrypt`, `nip04_encrypt`, `nip04_decrypt`.

**Methods (cheap, implement):** `switch_relays` — v1 replies `null` (keep the client on the mailbox already in its `nostrconnect` / `bunker` URI). Do not advertise the LAN `ws://` mailbox to a public HTTPS tab. The daemon still **dials every** `signerDial` URL so Mode A and Mode B can run at once. `logout` — drop the live session, keep ACL so Bitspark’s 7-day `toPayload()` restore still works.

**Do not implement:** `create_account`, NIP-05 login, policy/token RPC, admin npubs over Nostr.

### Pairing

- **`nostrconnect://` (default):** Bitspark mints client key + URI (`relay`, `secret`, `perms`, `name=Bitspark`) and **subscribes first**. User delivers the URI **out of band** (open signer UI with `?uri=`, or paste). Signer publishes a kind `24133` **connect response** (result = `secret`) to the client pubkey. Client checks `secret`, then `get_public_key`. Do not wait for a client `connect` request on this path — NDK’s `nostrconnect` flow does not send one.
- **`bunker://` (fallback):** URI is `bunker://<mailbox-pubkey>?relay=<client-facing-mailbox>`. Client sends `connect`. Parse params as `[target, secret, perms, metadata]` — empty secret is `""`. Never treat `perms` as the invitation token (nsecbunkerd “Token not found”).

After Approve, persist the **requested** perms on that client pubkey (not a hard-coded Bitspark-only ACL). Unknown client or method/kind outside the grant → pending in the UI (TTL 180s, longer than Bitspark’s 120s wait), not a silent error and not `auth_url`.

### Bitspark interop snapshot (what Approve must be able to grant)

Source of truth is `bitspark_btc` `NIP46_NOSTR_CONNECT_PERMS` at implementation time. Current list: `get_public_key`, `nip04_encrypt`, `nip04_decrypt`, `nip44_encrypt`, `nip44_decrypt`, and `sign_event` for kinds `0`, `1`, `3`, `5`, `7`, `13`, `9734`, `9041`, `1068`, `1018`, `34550`, `1111`, `1984`, `1100`, `1101`, `1104`, `1105`, `1106`, `1107`, `1108`, `30102`, `10002`, `10003`, `30003`.

Kind `13` is required for Gift Wrap / NIP-17. Do not require `14`, `1059`, `10050`, or `30103` unless Bitspark adds them to that perm list. If Bitspark later extends the list, user re-approves that client.

### Quiet vs prompt

| Request | Behavior |
| --- | --- |
| `ping` | Always |
| Approved client + granted method/kind | Sign / encrypt immediately |
| New client, or extra perm | Queue in UI until Approve / Deny (Bitspark waits up to 120s) |
| Revoked client | Error |
| Signer process stopped | No prompt (CONTRACT) |

## 6. Data (v1, on the app volume)

No Prisma, no `User` / username@domain, no token engine.

```text
wrap.key          # auto-unlock secret, mode 0600, never served over HTTP
user.ncryptsec    # NIP-49 of the user nsec
mailbox.ncryptsec # NIP-49 of the remote-signer (envelope) key
state.json        # { pubkey, backupShownAt, clients[], signerDial[], clientDial[], pending[] }
```

Atomic write (temp file + rename). `clients[]` is the ACL (pubkey, name?, url?, perms[], approvedAt, revokedAt?). Later multi-identity can nest this under `identities[]` without a protocol change.

**Wrap secret:** generate at first run and store in the volume. Anyone with the volume can decrypt. That matches “keys stay on the user’s Umbrel,” not “keys stay in the user’s head after every reboot.” Do not invent a KMS. Optionally wrap with Umbrel `APP_SEED` if it is already in the container env — same threat model.

## 7. Local control HTTP (not a signing API)

Bound to the UI port (Umbrel-authed in production; no login on localhost in dev). JSON only for the UI:

- First-run: generate / import nsec, confirm backup
- List / approve / deny pending
- List / revoke clients
- Get/set relay lists (two fields)
- Show `bunker://` for fallback copy
- `GET /connect?uri=nostrconnect://…` → Approve screen

Bitspark must not POST events here. Optional convenience: `window.open(signerUi + '/connect?uri=' + encodeURIComponent(nostrconnect))`.

## 8. Bitspark changes (SPA + Umbrel package)

Keep one NIP-46 path (`createNostrConnectSigner` / `createBunkerSigner`).

Do not bake Docker-internal hostnames into the SPA (nsecbunkerd `ws://relay:8080` in the browser). The tab already knows the host it used.

Umbrel Bitspark is a static image (`healthz` on port 80). Do not add an entrypoint that rewrites hostnames. Ship a **static** `umbrel/bitspark/signer-config.json` and bind-mount it into the SPA web root:

```json
{
  "mailboxPort": 8741,
  "signerUiPort": 8740
}
```

The SPA builds `ws://${location.hostname}:8741` and `http://${location.hostname}:8740`. **404 → not an Umbrel Bitspark build; do not show “Bitspark Signer.”** Public Bitspark has no file; existing “Use a remote signer” / bunker / NIP-07 stay. If the signer app is not running, the button may still show and connect times out with “install / start Bitspark Signer.”

v1 port constants (document in both `umbrel-app.yml` files):

| App | Port | Use |
| --- | --- | --- |
| Bitspark (existing) | 8734 | SPA (Umbrel-authed) |
| Bitspark Signer UI | 8740 | `umbrel-app.yml` `port`; Umbrel-authed |
| Bitspark Signer mailbox | 8741 | Compose `ports:` on the relay; **no** Umbrel cookie |

If a future Umbrel ignores extra `ports:`, fallback is `PROXY_AUTH_WHITELIST` for a `/relay` WebSocket on 8740 — do not design that first.

When config exists:

1. Prefill Nostr Connect relay with the constructed `ws://` mailbox (not `DEFAULT_RELAYS`).
2. Start `nostrconnect` and **wait** (subscribe), then open `signerUi/connect?uri=…` if the UI origin is http(s) on this host.
3. Popup blocked or Umbrel login in the way → user opens the signer app and pastes the URI.
4. No QR on this path.

Marketplace read/write relays stay `DEFAULT_RELAYS` / NIP-65. NIP-46 mailbox is independent.

## 9. Relays

| Who dials | Mode A default | Mode B |
| --- | --- | --- |
| Signer process | `ws://relay:8080` (Compose DNS) | that **plus** user-configured `wss://…` |
| Browser | `ws://<host>:<published-mailbox-port>` | the same `wss://…` the user set |

`clientDial` is what goes in `nostrconnect` / `bunker://` / Bitspark config. Mixed content: Umbrel Bitspark is HTTP + `ws://` (same as Umbrel Nostr Relay). Public Bitspark is HTTPS → mailbox **must** be `wss://`. The UI should say so when the user adds a public mailbox; do not try to TLS-terminate the local relay in v1.

Local relay storage: ephemeral is enough (kind 24133 is not meant to be archived). Signing mailbox vs Bitspark catalog data stay different relays.

## 10. New repo shape (do not overbuild)

Working name: `bitspark-signer`. Node 22, TypeScript, `nostr-tools` + `ws` (daemon). **NDK is the client under test (Bitspark), not the signer’s core.** Static UI (a few pages; Svelte without SvelteKit is fine if it stays small).

```text
src/daemon/     # keys, ACL, NIP-46, relay sockets
src/http/       # UI + control routes
src/ui/         # first-run, pending, clients, relays
docker-compose.yml   # signer + relay (dev; Umbrel reuses this pair)
umbrel/              # umbrel-app.yml + app_proxy wrapper
test/                # protocol unit tests + NDK client interop
```

Docker: two services (`signer`, `relay`). `relay` publishes `8741:8080`. One volume for signer data; relay db may be ephemeral (kind 24133 need not survive restart).

## 11. Implementation order (not tickets)

1. Daemon: generate/import, NIP-49, mailbox key, subscribe, `nostrconnect` response + `bunker://` `connect`, ACL, quiet `sign_event` / NIP-44.
2. UI: first-run, backup, pending Approve, revoke, two relay fields, copy bunker URI.
3. Compose (`signer` + bundled `relay`) + mailbox smoke + NDK client tests (this is Mode A on a laptop).
4. Manual: Bitspark `npm run dev` against `ws://127.0.0.1:8741`; then `npm run preview` + public `wss://` (Mode B). nsecbunkerd only as an optional strict extra, not the dev signer.
5. Umbrel package last (`app_proxy`, port 8741, bind-mount `signer-config.json`).
6. Stop. Multi-identity / QR / `auth_url` / hosted keys are later product decisions.

## 12. Verification

- `connect` param order: perms never occupy the secret slot.
- Mode A on a laptop (no Umbrel): bundled relay on `8741`, signer UI on `8740`, Bitspark `npm run dev`, one Approve, then kind `0` and kind `13`.
- Mode A on Umbrel: same, plus `app_proxy` and injected `signer-config.json`.
- Mode B: browser not on localhost-only relay; copy-link; Approve in signer UI.
- Other Bitspark sign-in options still work with the signer app stopped.
- No long-lived `nsec` in the SPA; no HTTP `POST /sign`; no LNBits/NWC in this app.
- `npm` tests in the new repo; Bitspark `npm run check` after the SPA wiring.

## 13. Explicit non-goals (v1)

nsecbunkerd admin RPC, `app.nsecbunker.com`, Prisma `User`, `create_account`, NIP-05 hosting, policy tokens, QR, `auth_url`, mDNS, custom HTTP signing, a third “relay” Umbrel app, operating a public mailbox, Mode C custody.

## 14. Contract coverage

| CONTRACT | Where |
| --- | --- |
| NIP-46 only; no HTTP signing | §1, §5, §7 |
| Kind 13 + NIP-44 + ping + connect + get_public_key | §5 |
| Two relay URL fields; local default; user can add `wss://` | §9 |
| New repo; nsecbunkerd = interop only | §1, §10 |
| One nsec, encrypt at rest, backup once | §6 |
| Hidden mailbox key; one identity in UI | §2, §6 |
| nostrconnect first; bunker fallback | §5 |
| Approve/deny/revoke in this UI | §7 |
| Injected mailbox + optional signer UI | §8 |
| Other NIP-46 signers stay | §8 |
| No nsec in SPA, no LN, no QR happy path, no Mode C | §3, §13 |

## 15. Done when

This file is sufficient to implement. Mode A on a laptop is Compose + Bitspark `npm run dev` (bundled local relay included). Umbrel is the same compose plus `app_proxy`. Mode B is the same binary plus a user-configured `wss://` mailbox. CONTRACT rows in §14 have components. Remaining packaging risk (Umbrel extra host port) has a named fallback. Further refinement is not required unless PRODUCT or CONTRACT changes.
