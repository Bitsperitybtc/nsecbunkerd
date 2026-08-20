# Bitspark Signer — architecture

Status: **ready to implement, except unlock policy** (ARCHITECTURE §6 — working assumption vs passphrase alternative). **Product:** [PRODUCT.md](./PRODUCT.md). **Contract:** [CONTRACT.md](./CONTRACT.md). **Line of thought:** [SIGNER-STRATEGY.md](./SIGNER-STRATEGY.md).

This is the build map: components, data, pairing, packaging. It does not reopen NIP-46 vs HTTP, wrap-vs-new, or hosted keys.

## 0. Stack

Bitspark Signer is the product on top. Build and prove from the bottom. Each layer must work without the layers above it.

```text
4. Product      Bitspark Signer: injected config, branded button, optional Approve popup, Mode A/B
3. Packaging    Umbrel app_proxy, ports, volume (not required to prove the signer)
2. Mailbox      bundled kind-24133 relay + signer-dial vs client-dial URLs
1. Signer       nsec, ACL, NIP-46, Approve UI — any NIP-46 client
```

v1 **software** is layers 1–2 (one compose: daemon + relay). v1 **product** is layers 3–4 (two Umbrel apps, Bitspark wiring). Do not start from the button.

## 1. What we are building

A **new** small NIP-46 remote signer (new git root). It holds one Nostr identity, approves clients in its own UI, and signs over a relay mailbox. Same protocol as Amber / nsec.app. nsecbunkerd is reference and interop target only.

The Umbrel product that ships is **Bitspark Signer**: that signer, packaged and wired so Bitspark can use it without assembling a third-party signer. Bitspark is the first client we enable, not a private API.

```text
  Any NIP-46 client               Mailbox                     Signer
  (throwaway                      (kind 24133,                user nsec + mailbox key
   client key)                    NIP-44 RPC)                 + client ACL + UI

  nostrconnect://  ──out of band──►  UI Approve
  kind 24133       ◄──── relay ────►  daemon

  Mailbox = bundled nostr-rs-relay (local default) and/or a user-configured wss://
```

Signing never uses HTTP. The signer’s HTTP port is only: local UI, setup, approve/deny/revoke, relay settings.

## 2. Contradictions resolved

Taken from PRODUCT / CONTRACT / STRATEGY / current NIP-46 / Bitspark’s client. CONTRACT wins on product scope; NIP-46 wins on wire format; Bitspark’s existing client wins on methods and `connect` param order for the first client.

| Tension | Resolution |
| --- | --- |
| Strategy sketches Mode C; CONTRACT parks hosted keys | **Out of v1 and not a design driver.** Identity + client ACL is a **signer** requirement (revoke, several clients on one key) — not because we plan to host keys. |
| Strategy Mode B mentions QR; CONTRACT forbids QR as Umbrel happy path | **No QR in v1.** Product Mode A: inject mailbox + optional open of signer UI. Mode B: copy `nostrconnect://`. Phone-as-remote-control is later. |
| Strategy “same-node discovery”; CONTRACT is config injection | **No mDNS / custom discovery.** Product layer: Umbrel writes a small JSON the Bitspark tab can fetch. Independent install and any other client still work via paste. |
| `auth_url` in NIP-46 and nsecbunkerd; CONTRACT wants in-app Approve | **Do not send `auth_url` in v1.** Pending requests live in this app’s UI. A client that waits on the relay (Bitspark does) can leave its `authUrl` handler idle. |
| Strategy “new app or module in this repo”; CONTRACT “new repo” | **New git root** (working name `bitspark-signer`). This folder stays the product/contract/architecture home until that repo exists. |
| Separate mailbox key vs “one identity” | **Two keys in storage, one npub in the UI.** `bunker://` uses the mailbox pubkey; `get_public_key` returns the user pubkey. Users never see a second connection string. |
| Bitspark still requests `nip04_*`; CONTRACT names NIP-44 | **Implement both.** Product flows are NIP-44 / kind 13. `nip04_*` exists so NDK `connect` perm lists (including Bitspark’s) do not fail. |
| Auto-start vs encrypt-at-rest | **Not frozen.** Disk is always NIP-49 (no `nsec1` file). **A (working assumption):** auto-unlock via `wrap.key` on the volume — quiet signing after reboot; volume theft ≈ having the nsec. **B (alternative):** user passphrase is the NIP-49 secret — real encryption; every container/Umbrel restart stays locked until someone types it in this UI. Pick before locking storage details; keep an unlock seam either way. See §6. |
| Local relay vs public client | **Bundled local relay is the default mailbox, not the only mailbox.** User can add a `wss://` relay both the home signer and a remote tab can open. We do not operate a public relay. |
| CONTRACT “inject browser-facing URL” vs ports-only JSON | **Product layer, same outcome.** Config ships mailbox/UI **ports**; the tab builds `ws://${location.hostname}:…` so Docker-internal names never leak. That *is* the browser-facing URL. The daemon does not read this file. |
| CONTRACT / freeze “publishes `connect`” vs NIP-46 `nostrconnect://` | **Happy path is client-initiated.** The client **listens** and hands the URI out of band; the signer publishes the connect **response**. `bunker://` is the flow where the client publishes `connect` first. CONTRACT protocol section now matches this. |
| Product name vs signer base | **Bitspark Signer is layer 4.** Layers 1–2 must pair and sign with a generic NIP-46 client before Bitspark or Umbrel exist in the loop. |

Unlock policy (A vs B in §6) is the remaining product choice. It does not reopen NIP-46. Implement encrypt/decrypt behind one unlock seam so the choice is not a rewrite.

## 3. Deployment (same binary)

Modes A and B are how the **product** uses the signer. They are not the shape of the daemon. The same binary serves any NIP-46 client.

### Mode A — Umbrel Bitspark + Umbrel signer (primary product path)

1. Install signer (creates or imports one identity, backup shown once).
2. Install Bitspark (independent; no hard Umbrel `dependencies:` on the signer).
3. Open Bitspark → **Bitspark Signer** (only if injected config is present) → optional popup/tab of signer UI → Approve once.
4. Further `sign_event` / NIP-44 from that client pubkey are quiet.

Mailbox = local relay in the signer compose. Browser-facing URL is injected; signer-facing URL is the Docker DNS name.

### Mode B — Public Bitspark + user-run signer

Same daemon and UI. User adds a reachable `wss://` mailbox in signer settings and uses that same URL in Bitspark’s Nostr Connect relay field (or a future “Bitspark Signer” path that still asks for the mailbox). Copy-link `nostrconnect://`, approve in the Umbrel signer UI. No `localhost` `auth_url`.

### Dev / test — layers 1–2, no Umbrel, no Bitspark required

Umbrel is **packaging** (`app_proxy`, one advertised UI port, volume paths). It is not required to develop or to prove NIP-46. Bitspark is not required to prove the signer.

Daily loop is Docker Compose in the new repo: the same two services as the Umbrel app (`signer` + `relay`), without `app_proxy`.

| Role | Dev (laptop) | Umbrel |
| --- | --- | --- |
| Signer UI | `http://127.0.0.1:8740` (no Umbrel login) | `http://<node>:8740` behind `app_proxy` |
| Mailbox (browser + host-run daemon) | `ws://127.0.0.1:8741` | `ws://<node>:8741` |
| Mailbox (daemon in Compose) | `ws://relay:8080` | `ws://relay:8080` |
| First client (optional) | Bitspark `npm run dev` / `npm run preview` | Bitspark app |

The two relay URL fields **may be equal** on a laptop (both `ws://127.0.0.1:8741` if the daemon runs on the host). Compose-internal vs published port is the same split as production.

**Local relay:** yes — it is a first-class sidecar of **this** signer (layer 2), not of Bitspark. `nostr-rs-relay`, kind `24133` allowlist, host port 8741. It is not a third Umbrel app, not Umbrel’s “Nostr Relay” store app, and not nsecbunkerd’s `PROFILE=local` stack. That NSEC-1 work is the pattern to copy, not a runtime dependency.

How to prove the **signer** (layers 1–2) without Bitspark or Umbrel:

1. `docker compose up` in `bitspark-signer` (relay + signer). Fast UI iteration: compose **only the relay**, run the daemon with `npm run dev` on the host, set `signerDial` = `ws://127.0.0.1:8741`.
2. Pair a generic NIP-46 client (NDK in tests: `nostrconnect` and `bunker://`). Approve in `http://127.0.0.1:8740`. Sign a kind `0` and a kind `13`.

How to exercise **product** Mode A without Umbrel (after the signer bar is green):

1. Same compose as above.
2. Bitspark `npm run dev -- --host 0.0.0.0`.
3. Pair: either existing **Use a remote signer** with relay `ws://127.0.0.1:8741`, or (once wired) the same `signer-config.json` as Umbrel so the tab builds `ws://localhost:8741` / `http://localhost:8740` from `location.hostname`. Local Vite: gitignored or `import.meta.env.DEV` only — **do not commit that file into `static/`** or the public production build will show “Bitspark Signer” against the wrong host.
4. Approve in `http://127.0.0.1:8740`. Then sign a kind `0` and a kind `13` from Bitspark.

Mode B without Umbrel: same signer, add a public `wss://` mailbox in signer settings, open Bitspark via `npm run preview` (or another origin) and put that `wss://` in the Nostr Connect relay field. Copy-link, approve in the local signer UI.

**Tests**

| Layer | What | Where | Bar |
| --- | --- | --- | --- |
| Unit | URI parse, `connect` param order, ACL, NIP-49, kind-13 grant | `bitspark-signer` `npm test` | signer |
| Mailbox smoke | publish/read kind 24133 on `ws://127.0.0.1:8741` | compose `relay` + a few lines of `nostr-tools` (same idea as nsecbunkerd `relay-smoke`) | signer |
| Interop | NDK `nostrconnect` + `bunker://` against the daemon | `bitspark-signer` tests using `@nostr-dev-kit/ndk` as **client** | signer |
| Manual A | Bitspark `npm run dev` + local compose | laptop | product |
| Manual B | Bitspark preview + `wss://` mailbox | laptop; signer still local | product |
| Umbrel last | `app_proxy`, extra host port, injected JSON mount | only when packaging | product |

Do not wait for an Umbrel node to start implementation. Do not stand up nsecbunkerd as the dev signer. Do not wait for Bitspark wiring to call the signer done.

### Not v1

- Hosted keys we operate (old Mode C).
- QR, phone push, NIP-89/NIP-05 discovery, multi-identity, Lightning/NWC, wrapping nsecbunkerd.

## 4. Components

Two containers in the signer (layers 1–2). Bitspark SPA is layer 4, elsewhere.

| Piece | Layer | Where | Role |
| --- | --- | --- | --- |
| **Daemon** | 1 | new repo, one Node process | Holds keys in memory after unlock; NIP-46 over relays; client ACL; serves UI + local control HTTP |
| **UI** | 1 | static pages from that process | First-run, backup, pending Approve, clients, relay settings, copy `bunker://` |
| **Mailbox relay** | 2 | `nostr-rs-relay` sidecar (same pattern as NSEC-1 and Umbrel’s Nostr Relay app) | Default **NIP-46 mailbox**, not a general personal relay. Set `event_kind_allowlist = [24133]`. Any NIP-46 client can use it; Damus-style kind `1` backup does not belong here (marketplace relays stay Bitspark’s). Kind `24133` is ephemeral (2xxxx): pairing needs the client **already subscribed** before Approve. |
| **Bitspark SPA** | 4 | `bitspark_btc` | Existing NIP-46 client (`nip46Bunker.ts`). Umbrel package **bind-mounts** static `signer-config.json`. Public site unchanged except it keeps Amber/bunker/NIP-07 |

Do not add a third Umbrel app for the relay. Do not implement a custom relay in the daemon.

### Why the mailbox is not the UI port

Umbrel `app_proxy` authenticates HTTP **and WebSocket upgrades**. A Bitspark tab is a different origin and will not reliably present the signer’s Umbrel cookie. Official Umbrel Nostr Relay therefore exposes `ws://umbrel.local:4848` without that login.

v1: **UI on the app’s main port (Umbrel-authed in packaging). Mailbox on a dedicated published WebSocket port (no Umbrel cookie).** NIP-46 is the access control. Do not put the mailbox behind Umbrel login.

## 5. Protocol (wire) — layer 1

Follow [NIP-46](https://github.com/nostr-protocol/nips/blob/master/46.md). Bitspark already speaks it via NDK; tests use NDK as a generic client.

**Methods (must):** `connect`, `get_public_key`, `ping`, `sign_event`, `nip44_encrypt`, `nip44_decrypt`, `nip04_encrypt`, `nip04_decrypt`.

**Methods (cheap, implement):** `switch_relays` — v1 replies `null` (keep the client on the mailbox already in its `nostrconnect` / `bunker` URI). Do not advertise the LAN `ws://` mailbox to a public HTTPS tab. The daemon still **dials every** `signerDial` URL so a local mailbox and a public mailbox can run at once. `logout` — drop the live session, keep ACL so a client that restores a session (Bitspark’s 7-day `toPayload()`) still works.

**Do not implement:** `create_account`, NIP-05 login, policy/token RPC, admin npubs over Nostr.

### Pairing

- **`nostrconnect://` (default):** Client mints a client key + URI (`relay`, `secret`, `perms`, `name`) and **subscribes first**. User delivers the URI **out of band** (open signer UI with `?uri=`, or paste). Signer publishes a kind `24133` **connect response** (result = `secret`) to the client pubkey. Client checks `secret`, then `get_public_key`. Do not wait for a client `connect` request on this path — NDK’s `nostrconnect` flow does not send one.
- **`bunker://` (fallback):** URI is `bunker://<mailbox-pubkey>?relay=<client-facing-mailbox>`. Client sends `connect`. Parse params as `[target, secret, perms, metadata]` — empty secret is `""`. Never treat `perms` as the invitation token (nsecbunkerd “Token not found”).

After Approve, persist the **requested** perms on that client pubkey (not a hard-coded Bitspark-only ACL). Unknown client or method/kind outside the grant → pending in the UI (TTL 180s; Bitspark waits 120s), not a silent error and not `auth_url`.

### First client — Bitspark interop snapshot

This is what Bitspark will request. It is not the signer’s allowlist. Source of truth is `bitspark_btc` `NIP46_NOSTR_CONNECT_PERMS` at implementation time. Current list: `get_public_key`, `nip04_encrypt`, `nip04_decrypt`, `nip44_encrypt`, `nip44_decrypt`, and `sign_event` for kinds `0`, `1`, `3`, `5`, `7`, `13`, `9734`, `9041`, `1068`, `1018`, `34550`, `1111`, `1984`, `1100`, `1101`, `1104`, `1105`, `1106`, `1107`, `1108`, `30102`, `10002`, `10003`, `30003`.

Kind `13` is required for Gift Wrap / NIP-17. Do not require `14`, `1059`, `10050`, or `30103` unless Bitspark adds them to that perm list. If Bitspark later extends the list, user re-approves that client.

### Quiet vs prompt

| Request | Behavior |
| --- | --- |
| `ping` | Always |
| Approved client + granted method/kind | Sign / encrypt immediately |
| New client, or extra perm | Queue in UI until Approve / Deny (Bitspark waits up to 120s) |
| Revoked client | Error |
| Signer process stopped | No prompt (CONTRACT) |

## 6. Data (v1, on the app volume) — layer 1

No Prisma, no `User` / username@domain, no token engine. No plaintext `nsec` file.

The container’s own filesystem is **ephemeral**. Identity lives on a **Docker/Umbrel volume** mounted into the signer container at `DATA_DIR` (compose: `/data`). Reboot Umbrel or recreate the container: the image is new, the volume is the same directory.

```text
# inside the signer container, path = $DATA_DIR  (e.g. /data)
wrap.key          # Option A only: auto-unlock passphrase for the ncryptsec files; mode 0600
user.ncryptsec    # NIP-49 ciphertext of the user nsec
mailbox.ncryptsec # NIP-49 ciphertext of the mailbox (envelope) key
state.json        # schemaVersion, pubkey, backupShownAt, clients[], signerDial[], clientDial[], pending[]
```

Compose sketch: `volumes: [ signer-data:/data ]` and `environment: DATA_DIR=/data`. Umbrel uses the app’s declared volume the same way. Host `npm run dev`: `DATA_DIR=./data` on the laptop disk.

Atomic write (temp file + rename). `clients[]` is the ACL (pubkey, name?, url?, perms[], approvedAt, revokedAt?). Later multi-identity can nest this under `identities[]` without a protocol change.

### Restart / reboot (memory vs disk)

Plaintext nsec exists **only in process memory**, so a container stop, crash, or Umbrel reboot **wipes it**. That is intended. How the process gets the nsec back is the unlock policy (§6 below).

If the volume is gone, identity is gone (unless they still have the `nsec1` they wrote down).

```text
  Umbrel disk (volume)              Running process
  /data/user.ncryptsec    ──NIP-49─► nsec in RAM (until exit)
  /data/mailbox.ncryptsec ──NIP-49─► mailbox key in RAM
  /data/state.json        ──read──►  ACL, relays
  passphrase source       ──varies─► wrap.key (A) or user typed (B)
```

### Where the nsec comes from

Never from env, compose, Docker secrets, or a file drop. Two first-run actions in this UI:

| Path | What the user does | Then |
| --- | --- | --- |
| **Generate** | Clicks create | Daemon makes a random nsec in memory, encrypts it to `$DATA_DIR/user.ncryptsec`, shows the `nsec1…` **once**, requires a confirm that they copied it. `backupShownAt` set. |
| **Import** | Pastes `nsec1…` or 64-char hex | Validate, encrypt to `$DATA_DIR/user.ncryptsec`, wipe the request body. They already held the secret; confirm “I have a backup” — do not echo the nsec again as a default screen. |

Until `$DATA_DIR/user.ncryptsec` exists: Setup only; do not subscribe. That is the encrypted nsec on the **volume**, not the ephemeral container disk.

Reject npub, BIP39 seed phrases, and `ncryptsec` import in v1 (decrypt elsewhere and paste `nsec`). After either path, generate the mailbox key the same way (never shown) into `mailbox.ncryptsec`. Same NIP-49 passphrase as the user key (A: `wrap.key`; B: the user’s passphrase).

Replacing the identity later is a new product decision (wipe volume or a dedicated “reset identity”). v1 has one nsec per install.

### Unlock policy — not frozen

Pinned for both options: NIP-49 on disk; plaintext only in RAM; never `nsec` in env; volume at `DATA_DIR`; generate/import in this UI.

Keep **one unlock seam** in the daemon (passphrase in → decrypt ncryptsec → RAM). Do not scatter `wrap.key` reads. A vs B should be a policy choice, not a rewrite.

#### Option A — auto-unlock (working assumption)

Why it was the default: Umbrel enablement is unattended. Reboot, container restart, power blip → signer comes back and quiet signing works. A passphrase every boot recreates nsecbunkerd’s “it isn’t unlocked” failure, and Bitspark only waits ~120s with no prompt if the process is down.

How: daemon writes `wrap.key` (random, high-entropy) into `$DATA_DIR` on first container start, before Setup. That file **is** the NIP-49 passphrase. It is not typed by the user, not in env, not returned over HTTP. On every start: read `wrap.key` → decrypt → RAM → subscribe.

Honesty: **`wrap.key` next to `user.ncryptsec` is not confidentiality against volume theft.** Anyone with the app volume can decrypt. Encryption still means: no `nsec1` on disk to grep; a leaked `user.ncryptsec` *alone* is inert; the file format can take a real passphrase later. Disk/root on the node is the trust boundary (“keys stay on this Umbrel”).

Optional extra in A: mix Umbrel `APP_SEED` if it is already in the container env. That makes “rsync only the app folder” harder; full-disk theft still wins. Same threat model, not a user password.

#### Option B — user passphrase after every process start (alternative)

The NIP-49 passphrase **is a password the user chooses** at Generate/Import. There is **no** `wrap.key`. On every container start, crash recovery, or Umbrel reboot the process is **locked**: Setup/Unlock UI only, `healthz.unlocked = false`, no mailbox subscribe, no `sign_event` until they type it in this app.

| What you get | What you give up |
| --- | --- |
| Volume copy without the passphrase is inert ciphertext | Quiet signing after reboot is gone |
| Forgot-password path = `nsec1` backup + Import on a fresh volume (ACL gone) | “Two apps, done” becomes “two apps, then unlock after every restart” |
| Matches Amber-like “signer is a locked box” | Bitspark pairing/sign waits (~120s) fail while locked; need copy: open signer and unlock |
| | nsecbunkerd-style “daemon is up but not signing” support load |

**Still to consider if we pick B** (do not invent these after the fact):

- **When collected:** same screen as Generate/Import; confirm twice; minimum length. Empty passphrase is Option A in disguise — forbid it.
- **Unlock view:** first-class (not a modal on Home). Pending Approve while locked: show “unlock first,” do not start the 180s TTL until unlocked.
- **Product copy:** Bitspark when the signer is reachable but not signing: “Bitspark Signer is locked — open it and unlock.” Distinguish from “app not installed.”
- **Forgot / change:** forgot = Import `nsec1` on wiped volume. Change passphrase = decrypt with old, re-encrypt both ncryptsec files, no `nsec` echo.
- **Mailbox key:** same passphrase as the user key. One unlock unlocks both.
- **Stay unlocked:** until the process exits (same as A once in RAM). No idle lock in v1 unless we add it later.
- **Choose at Setup vs one policy for all installs:** one policy for v1 is simpler. Per-install choice means two support stories and a `state.json` flag.
- **Umbrel login ≠ unlock.** `app_proxy` auth does not decrypt keys. Option B is a second step after opening the app.
- **Compose healthcheck:** process can be healthy while locked. Do not treat `unlocked: false` as a failed container or Docker will restart-loop.

#### Option C — not a third product

`APP_SEED` (or any secret *outside* `DATA_DIR`) as the NIP-49 passphrase: auto-unlock like A, slightly stronger against “copied the app folder only.” Still not B. Mentioned so we do not confuse it with a user password.

### Config seeds (env) — not identity

Seeds tell the process **where to listen and where to write**. They are not the nsec.

| Variable | What it is | Why it exists |
| --- | --- | --- |
| `DATA_DIR` | Filesystem path **inside the container** for the four files above | Docker images are disposable. Without a mounted dir, reboot = empty disk = Setup again. Compose default `/data` (volume). Host dev `./data`. |
| `LISTEN` | `host:port` for UI + control HTTP | Bind all interfaces in a container (`0.0.0.0:8740`); localhost-only on a laptop. |
| `DEFAULT_SIGNER_DIAL` | Mailbox WebSocket the **daemon** opens if `state.json` has no `signerDial` yet | In compose the relay is `ws://relay:8080` (Docker DNS). On the host it is `ws://127.0.0.1:8741`. |
| `DEFAULT_CLIENT_DIAL` | Optional seed for `bunker://` copy | Laptop: `ws://127.0.0.1:8741`. Umbrel: **unset** — the container does not know the node hostname. |
| `LOG_LEVEL` | `error` / `info` / `debug` | DX. Default `info`. |

After the UI saves relays or ACL, `state.json` wins. Changing relays reconnects sockets without restarting the container. Re-reading env must not overwrite user relays.

Do not add `NSEC`, `WRAP_KEY`, `MAILBOX_NSEC`, or any ACL in env.

Relay sidecar: static `config.toml` in the image or a compose mount (`event_kind_allowlist = [24133]`, listen `0.0.0.0:8080`). Not in `state.json`.

Product `signer-config.json` (Bitspark): ports only. Daemon never reads it.

### `state.json` schema

Include `schemaVersion: 1`. On boot: missing version → treat as 1; missing arrays → `[]`. Migrations are additive (new fields, defaults). If `schemaVersion` is **newer** than this binary: refuse to start (log and exit) — do not clobber. No Prisma.

### Volume backup and restore

Two backups, different jobs:

| Backup | What | Restores | Loses |
| --- | --- | --- | --- |
| Human (generate screen) | `nsec1…` written down | Identity on a **fresh** volume via Import | ACL, pending, relay lists. Under B this is also forgot-passphrase. |
| Node, Option A | `wrap.key` + both `.ncryptsec` + `state.json` | Identity **and** ACL, auto-unlock | nothing if the copy is complete. `wrap.key` must travel with the ncryptsec files. |
| Node, Option B | both `.ncryptsec` + `state.json` (no `wrap.key`) | Identity **and** ACL only after **Unlock** with the passphrase | ciphertext without the password is inert |

Restore: stop, replace the volume files, start. v1 does **not** add “download a zip of keys” in the UI. Umbrel volume backup / copying `DATA_DIR` is the node backup. Re-show nsec behind an explicit confirm is optional ease-of-life; default is still “shown once.”

## 7. Local control HTTP and views — layer 1

Bound to the UI port (Umbrel-authed in production; no login on localhost in dev). JSON only for the UI. `GET /healthz` is unauthenticated and returns no secrets: `{ ok, unlocked, mailboxConnected, npub | null }`.

Control actions:

- First-run: generate / import nsec, confirm backup; if Option B, set passphrase
- Unlock (Option B only): submit passphrase → decrypt into RAM
- List / approve / deny pending
- List / revoke clients
- Get/set relay lists (two fields)
- Show `bunker://` for fallback copy
- `GET /connect?uri=nostrconnect://…` → Approve screen

No client may POST events here. Product convenience (layer 4): Bitspark may `window.open(signerUi + '/connect?uri=' + encodeURIComponent(nostrconnect))`. That must not be the only pairing path.

### Views (v1)

| View | Must | Notes |
| --- | --- | --- |
| Setup | yes | Generate or import; gate everything else; Option B: choose passphrase here |
| Unlock | Option B | After every process start until passphrase entered |
| Home / status | yes | npub, mailbox up/down, pending count, paste `nostrconnect://`; `unlocked` |
| Pending / Approve | yes | Including `/connect?uri=` |
| Clients | yes | Revoke |
| Relays | yes | Two URL fields; mixed-content warning when adding `wss://` |
| Copy `bunker://` | yes | Needs `clientDial`; empty until seeded or user-set |
| Activity (last N) | useful | Client, kind, time — never event content / NIP-44 plaintext |

One identity in the chrome. Do not show the mailbox pubkey as a second user. Umbrel login is the lock on the HTTP UI in production; it does **not** decrypt keys. Option A has no app password. Option B’s passphrase is for NIP-49, not a second Umbrel user.

### Pending TTL when the user is late

Approve is valid for **180s** (Bitspark waits 120s). After expiry: do not approve; keep the row ~15 minutes as **expired — client timed out**, then drop. Deny still clears it. Empty queue with no explanation is a bug.

### Popup blocked

Bitspark always shows a copyable `nostrconnect://` (popup is extra). Signer home always has paste. `/connect?uri=` is the fast path when `window.open` works. If the popup is blocked or Umbrel login sits in front, paste still delivers the URI. The signer sees no pending relay event until that URI arrives (`bunker://` is the flow where the client publishes `connect` first).

## 8. Product layer — Bitspark SPA + Umbrel package

Keep one NIP-46 path (`createNostrConnectSigner` / `createBunkerSigner`). The signer does not need this file to run.

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

## 9. Relays — layer 2

| Who dials | Mode A default | Mode B |
| --- | --- | --- |
| Signer process | `ws://relay:8080` (Compose DNS) | that **plus** user-configured `wss://…` |
| Browser | `ws://<host>:<published-mailbox-port>` | the same `wss://…` the user set |

`clientDial` is what goes in `nostrconnect` / `bunker://` / Bitspark config. Mixed content: Umbrel Bitspark is HTTP + `ws://` (same as Umbrel Nostr Relay). Public Bitspark is HTTPS → mailbox **must** be `wss://`. The UI should say so when the user adds a public mailbox; do not try to TLS-terminate the local relay in v1.

Local relay storage: ephemeral is enough (kind 24133 is not meant to be archived). Signing mailbox vs Bitspark catalog data stay different relays.

## 10. New repo shape (do not overbuild)

Working name: `bitspark-signer`. Node 22, TypeScript, `nostr-tools` + `ws` (daemon). **NDK is a client under test, not the signer’s core.** Bitspark is the first real client; tests must not require its UI. Static UI (a few pages; Svelte without SvelteKit is fine if it stays small).

```text
src/daemon/     # keys, ACL, NIP-46, relay sockets
src/http/       # UI + control routes
src/ui/         # first-run, pending, clients, relays
docker-compose.yml   # signer + relay (dev; Umbrel reuses this pair)
umbrel/              # umbrel-app.yml + app_proxy wrapper
test/                # protocol unit tests + NDK client interop
```

Docker: two services (`signer`, `relay`). `relay` publishes `8741:8080`. One volume for signer data; relay db may be ephemeral (kind 24133 need not survive restart). Signer env: `DATA_DIR`, `LISTEN`, `DEFAULT_SIGNER_DIAL`, `LOG_LEVEL` (and `DEFAULT_CLIENT_DIAL` only in the laptop override).

**Logs (JSON lines).** `LOG_LEVEL=info` default. Log mailbox connect/disconnect, client approve/revoke, `sign_event` kind + client name/prefix. `debug` may add method names and pubkey prefixes. **Never** log `nsec`, `ncryptsec`, `wrap.key`, connect `secret`, event content, or NIP-44 plaintext. Compose `healthcheck` hits `GET /healthz`.

## 11. Implementation order (not tickets)

1. **Signer:** daemon — generate/import, NIP-49, **unlock seam** (A: `wrap.key` / B: user passphrase), mailbox key, subscribe only when unlocked, `nostrconnect` response + `bunker://` `connect`, ACL, quiet `sign_event` / NIP-44.
2. **Signer:** UI — first-run (generate **or** import), backup, Unlock view if B, pending Approve, revoke, two relay fields, copy bunker URI, paste URI on home, expired-pending state, `/healthz`.
3. **Mailbox:** compose (`signer` + bundled `relay`) + mailbox smoke + NDK client tests. **Signer bar:** this is done without Bitspark.
4. **Product (manual):** Bitspark `npm run dev` against `ws://127.0.0.1:8741`; then `npm run preview` + public `wss://` (Mode B). nsecbunkerd only as an optional strict extra, not the dev signer.
5. **Packaging last:** Umbrel (`app_proxy`, port 8741, bind-mount `signer-config.json`).
6. Stop. Multi-identity / QR / `auth_url` / hosted keys are later product decisions. Unlock A vs B is the open choice in §6, not this list.

## 12. Verification

**Signer bar (required before product work)**

- `connect` param order: perms never occupy the secret slot.
- Compose + NDK client: bundled relay on `8741`, signer UI on `8740`, one Approve, then kind `0` and kind `13`. No Bitspark UI.
- Generate and import first-run both produce `user.ncryptsec`; no plaintext nsec on disk; no nsec in env.
- Unlock seam: A auto-unlocks after compose up; B stays `unlocked: false` until passphrase; do not healthcheck-fail on locked.
- Expired pending cannot be approved; popup-blocked pairing still works via paste.
- No HTTP `POST /sign`; no LNBits/NWC in this app.
- `npm` tests in the new repo.

**Product bar**

- Mode A on a laptop (no Umbrel): same compose, Bitspark `npm run dev`, one Approve, then kind `0` and kind `13`.
- Mode A on Umbrel: same, plus `app_proxy` and injected `signer-config.json`.
- Mode B: browser not on localhost-only relay; copy-link; Approve in signer UI.
- Other Bitspark sign-in options still work with the signer app stopped.
- No long-lived `nsec` in the SPA.
- Bitspark `npm run check` after the SPA wiring.

## 13. Explicit non-goals (v1)

nsecbunkerd admin RPC, `app.nsecbunker.com`, Prisma `User`, `create_account`, NIP-05 hosting, policy tokens, QR, `auth_url`, mDNS, custom HTTP signing, a third “relay” Umbrel app, operating a public mailbox, Mode C custody, `NSEC=` in env, BIP39 / `ncryptsec` import in v1, “download keys zip” in the UI.

## 14. Contract coverage

| CONTRACT | Layer | Where |
| --- | --- | --- |
| Complete NIP-46 signer without Bitspark | signer | §0, §1, §3 tests, §11, §12 |
| NIP-46 only; no HTTP signing | signer | §1, §5, §7 |
| Kind 13 + NIP-44 + ping + connect + get_public_key | signer | §5 |
| Two relay URL fields; local default; user can add `wss://` | mailbox | §9 |
| New repo; nsecbunkerd = interop only | signer | §1, §10 |
| One nsec, NIP-49 at rest, backup once; never via env | signer | §6 |
| Unlock A vs B (not frozen) | signer | §6 |
| Env seeds boot; UI `state.json` wins after | signer | §6 |
| Hidden mailbox key; one identity in UI | signer | §2, §6 |
| nostrconnect first; bunker fallback | signer | §5 |
| Approve/deny/revoke in this UI | signer | §7 |
| Pending TTL / popup paste fallback | signer / product | §7 |
| Logs + `/healthz`; no secrets in either | signer | §7, §10 |
| Injected mailbox + optional signer UI | product | §8 |
| Other NIP-46 signers stay | product | §8 |
| No nsec in SPA, no LN, no QR happy path, no Mode C | product / signer | §3, §13 |

## 15. Done when

This file is sufficient to implement **once unlock policy is chosen** (or the unlock seam is built to accept either). Two bars:

- **Signer done:** Compose + NDK interop (bundled local relay included). CONTRACT signer rows in §14 have components. Under A, interop works after compose up. Under B, tests must unlock (or inject the passphrase in-process) before `sign_event`.
- **Product done:** Mode A on a laptop is that compose + Bitspark `npm run dev`. Umbrel is the same compose plus `app_proxy`. Mode B (public Bitspark) is the same binary plus a user-configured `wss://` mailbox. CONTRACT product rows in §14 have components. Remaining packaging risk (Umbrel extra host port) has a named fallback.

### Still open (do not reopen NIP-46)

- **Unlock policy (A / B / maybe per-install).** Product choice. Implications and leftover B details are in §6.
- Packaging nits, not design: pinned `nostr-rs-relay` image, restart/`depends_on`, Dockerfile vs bind-mount for `npm run dev`.

Further protocol refinement is not required unless PRODUCT or CONTRACT changes. Unlock is the exception.
