# Umbrel signer — line of thought and approach

Status: line of thought. **Product:** [PRODUCT.md](./PRODUCT.md). **Contract:** [CONTRACT.md](./CONTRACT.md). Not a commitment to reuse nsecbunkerd.

This document captures:

- what NIP-46 is for us
- why a signer Umbrel app is the enablement path
- how that holds if Bitspark is also publicly hosted
- what is required now vs later (multi-user)
- a possible way to approach the work

## What we already agree on

- Bitspark is a static SPA. It must not hold a long-lived `nsec`.
- Identity (Nostr signing) and wallet (Lightning / NWC) stay separate. This signer does not create LNBits wallets or replace NWC.
- Bitspark already speaks **NIP-46**. It must keep working with **any** compliant remote signer (Amber, nsec.app, Alby, this app, …).
- The Umbrel app **is a NIP-46 signer**, not a private Bitspark-only signing API. **Bitspark Signer** is the product name on top of that signer.
- nsecbunkerd is one existing NIP-46 implementation. It is **not** the product we want to ship as-is. It was built as a multi-tenant hosted bunker (admin RPC, `app.nsecbunker.com`, web-auth `User` rows, `create_account`, policies/tokens). That extra product is why local setup felt unusable.
- Decision: **NIP-46 yes; nsecbunkerd’s product shape no; implement a small signer that speaks the same protocol.** Use nsecbunkerd as a reference and interop target.

## Software stack (not the same as decision layers)

Job / protocol / deployment / implementation in [signer-product-decisions.md](../workflows/signer-product-decisions.md) are how we decide. This is how we **build**. Each layer must stand without the ones above it.

```text
4. Product      Bitspark Signer: injected config, branded button, optional Approve popup, Mode A/B
3. Packaging    Umbrel app_proxy, ports, volume
2. Mailbox      bundled kind-24133 relay + two URL fields
1. Signer       nsec, ACL, NIP-46, Approve UI — any NIP-46 client
```

The shipped app can be called Bitspark Signer. Layers 1–2 must already be a real remote signer (pair and sign with NDK or any other client) before Bitspark or Umbrel enter the loop.

## What NIP-46 is (short)

NIP-46 is a protocol for a **client** (Bitspark in the browser) to ask a **remote signer** (this Umbrel app) to sign and encrypt, without the client ever seeing the user `nsec`.

They do not use a private HTTP API. They leave encrypted **kind 24133** messages on a **relay** (a mailbox both sides can reach).

Three keys:

| Key | Who holds it | Role |
| --- | --- | --- |
| User key | Signer | The Nostr identity (`nsec` / `npub`). Signs notes, DMs, contracts. |
| Remote-signer key | Signer | Envelope key for NIP-46 traffic. May be the same as the user key. |
| Client key | Bitspark tab | Throwaway. Encrypts requests to the signer. Deleted on logout. |

Two ways to pair:

- `nostrconnect://…` — Bitspark starts; user opens/scans that in the signer (preferred).
- `bunker://…` — signer starts; user pastes the URI into Bitspark (fallback).

After `connect`, Bitspark needs at least: `get_public_key`, `sign_event` (including kind 13 seals), `nip44_encrypt` / `nip44_decrypt`, `ping`.

If the signer does not yet trust this client, it can return an `auth_url` for a browser approval page. That is optional. Approval can happen entirely inside the signer’s own UI.

## The same-box assumption — and where it is not enough

A useful default for Umbrel:

> Same box as Bitspark, we control install and LAN, joining is “install two Umbrel apps, open Bitspark, done.”

That is the **primary enablement path**. It is not the only deployment.

If we designed *only* for same-box:

- a local relay would be enough
- pairing could be localhost / LAN discovery
- `auth_url` on `http://localhost:…` would work

That breaks as soon as Bitspark is a public website, or the user opens public Bitspark while the signer is at home.

NIP-46 exists precisely so an **untrusted public website** can use a **signer the user controls**. We should keep that. The Umbrel app is how we enable people without forcing third-party signers. Third-party signers remain a fallback, not the happy path we tell Umbrel users to assemble.

## Deployment modes

Modes A and B are how the **product** uses the signer. They are not the shape of the daemon. Same signer implementation; different where Bitspark and the relay live. Do not fork the protocol per mode.

```text
                    ┌─────────────────────────┐
                    │  Any NIP-46 client       │
                    │  (Bitspark Umbrel/public │
                    │   or other Nostr apps)   │
                    └───────────┬─────────────┘
                                │ kind 24133
                                ▼
                    ┌─────────────────────────┐
                    │  Relay (local and/or     │
                    │   reachable public)      │
                    └───────────┬─────────────┘
                                │
                                ▼
                    ┌─────────────────────────┐
                    │  This signer (Umbrel or  │
                    │   later hosted)          │
                    │  holds nsec, approves    │
                    │  clients                 │
                    └─────────────────────────┘
```

### Mode A — Umbrel Bitspark + Umbrel signer (same node)

Primary onboarding.

- Install signer app (creates/import one identity, backup once).
- Install Bitspark app.
- Local relay on the node; both apps use it by default.
- Pairing: Umbrel injects the browser-facing mailbox (and optional signer UI URL); `nostrconnect`, not paste-URI as the happy path. Paste still works if injection is missing or for any other client.
- First launch: one approval, “Bitspark on this node may sign as this identity.”
- After that, signing is quiet unless a **new** client appears.

This is “two apps, done.”

### Mode B — Public Bitspark + user’s own signer

This is in scope for the design, not a later surprise.

Public Bitspark is still a static SPA. It must not hold the `nsec`. The user runs **this same signer** (typically on Umbrel at home). They meet over NIP-46.

What changes vs Mode A:

- The **browser** (on whatever network) and the **signer** (at home) must share a **relay both can reach**. A relay that only listens on `ws://127.0.0.1:7777` is not enough here.
- Pairing is `nostrconnect` (QR / copy from public Bitspark, approve in the Umbrel signer UI) or paste `bunker://` as fallback.
- Approval should happen **in the signer UI on the Umbrel**, not via `http://localhost:3009/requests/…` opened from a public site. Localhost auth URLs only work on the LAN and were a large part of the nsecbunkerd pain.
- The signer may still *also* use a local relay for Mode A and for other local apps.

This mode is why the app is a NIP-46 signer rather than “Bitspark calls HTTP on localhost.” A private API cannot serve public Bitspark without putting keys on the web host or inventing a second protocol.

We run the signer; we do not have to run Bitspark. Users do not depend on Amber/nsec.app unless they choose to.

### Mode C — Public Bitspark + a signer *we* host

Consider this as a **possible later deployment of the same app**, not as v1, and not as a different protocol.

Here we (or an operator) run the signer as a service. Users get an identity without running Umbrel. That is nsecbunker’s original product: many users, `create_account`, hosted admin.

Implications:

- This is **custodial** (or semi-custodial): we hold or can use their `nsec`. That is a different trust story than Mode A/B. Be explicit in UX and legal/product text if we ever do it.
- **Multi-user** stops being an extension and becomes the product.
- Relays must be public and reliable; local relay is irrelevant for the client.
- Onboarding can be smoother (no Umbrel), at the cost of “you trust us with signing.”

We should **not** build Mode C first. We **should** avoid v1 choices that make Mode C a rewrite (for example a single hard-coded identity with no notion of “this client is allowed to use this key”).

If we never host keys, Mode C can stay a sketch. Mode B already lets public Bitspark users sign with infrastructure they (or we) run on Umbrel.

### Mode D — Any other NIP-46 signer

Always supported in Bitspark. Not our enablement path. No work in this Umbrel app except staying spec-compliant so those signers and ours look the same to Bitspark.

## Relays: local as a convenient safe option, not a restriction

A local relay on the Umbrel (see the existing local-stack work: clean `nostr-rs-relay`, host port, smoke publish/read) is the right **default for Mode A**:

- no third-party mailbox for signing traffic
- works offline/LAN
- simple first-run

It must not be the only option.

| Situation | Relay the **signer** dials | Relay the **browser** dials |
| --- | --- | --- |
| Mode A, same node | Local relay on Docker/Umbrel network | Local relay as the user reaches it (localhost or node IP) |
| Mode B, public Bitspark | Local relay **and/or** a reachable relay | A relay the public SPA can open (public wss, or a published URL of *our* relay) |
| Mode C, hosted signer | Public relay(s) we operate or trust | Same |

nsecbunkerd already stumbled on “one URL for container and browser.” The new signer should treat **signer-facing** and **client-facing** relay URLs as two fields from day one, even if they are equal in simple setups.

Users who want nos.lol / Damus / their own relay should be able to set that. Local-only is the easy safe default, not a lock-in.

Bitspark’s own relay list for reading the marketplace is separate. NIP-46 only needs a mailbox both signer and *that browser tab* share.

## Multi-user as an extension, not v1

v1 can be **one signing identity per signer install** (plus a list of approved **clients** — Bitspark tab, maybe Damus later).

Design so this can grow without a new protocol:

- Identity (key) and client (approved browser/app pubkey) are different records.
- Several clients can use one identity.
- Later: several identities in one installer (household, “work” vs “personal”), each with its own client ACL.
- Later still: Mode C (many users on a hosted instance).

v1 does **not** need: username@domain web users, NIP-05 hosting, `create_account`, policy/token engines, admin npubs over Nostr.

v1 **does** need: revoke a client, list who is allowed, encrypted key at rest, backup of `nsec`.

## What to take from nsecbunkerd — and what not to

Keep (as requirements, not as code we must wrap):

- Encrypted `nsec` at rest, unlocked to run.
- Per-client approval (this browser may `connect` / `sign_event` / NIP-44).
- NIP-46 methods Bitspark already uses (including kind 13 and NIP-44).
- Optional `bunker://` for interop.
- The lesson that relay URLs for daemon vs browser must be split.

Drop / do not ship as the happy path:

- `app.nsecbunker.com` and admin RPC as the way to approve clients
- bcrypt `User` matching `wild@leaf` for a `/requests` page
- `create_account`, NIP-89 provider discovery, LNBits
- Documenting the hosted admin UI as primary
- Three identities + two connection strings as user-facing concepts (implementation may still use a separate envelope key; users should see one identity)

Do not repackage nsecbunkerd and “fix UX” as the plan. The UX problems are the product shape. A small new daemon that Bitspark’s existing NIP-46 client can talk to is the plan. nsecbunkerd remains useful to test against (“strict bunker” behaviour, `connect` param order).

## v1 requirements

**Must — signer (base)**

- Generate or import one `nsec` in this UI only (never env); NIP-49 on disk; show backup once on generate. Unlock after reboot is open (auto vs passphrase) — see ARCHITECTURE §6.
- Speak NIP-46: `connect`, `get_public_key`, `sign_event` (including kind 13), `nip44_encrypt` / `nip44_decrypt`, `ping`.
- Pairing via `nostrconnect://`; `bunker://` available.
- Approve/deny/revoke clients in **this app’s UI** (not a hosted admin SPA).
- Default to a **local relay**; allow additional/public relays.
- Distinct signer-dial vs client-dial relay URLs.
- Prove with a generic NIP-46 client (NDK in tests) before Bitspark wiring.

**Must — product (Bitspark Signer)**

- First-run pairing with Bitspark via `nostrconnect://` on the injected mailbox.
- Stay usable as the signer for **public** Bitspark (Mode B) without a second protocol.

**Must not (v1)**

- Treat the signer as incomplete until Bitspark is wired.
- Require third-party signers for Umbrel users.
- Require `app.nsecbunker.com`.
- Mix in Lightning / NWC.
- Put the `nsec` in the Bitspark SPA.

**Should (design for, implement later)**

- Multiple identities per install.
- Hosted multi-user deployment (Mode C), only if we explicitly accept custody.
- Optional `auth_url` for clients that are not our UI (other NIP-46 apps).
- User passphrase unlock after reboot (if we leave auto-unlock as default).

## Possible plan of approach

This is a sequence for thinking and building, not a ticket dump.

### 1. Freeze the job, not the old codebase

Write a one-page product contract (this folder can grow into that):

- Base: a complete NIP-46 signer (any client). Product name can still be Bitspark Signer.
- Umbrel users: Mode A, two apps, done.
- Public Bitspark users who run our signer: Mode B.
- Everyone else: any NIP-46 signer in Bitspark (already true).
- Local relay default; public/reachable relay optional.
- Multi-user later, data model not a dead end.

Do not start from nsecbunkerd issues as the backlog of the Umbrel app.

### 2. Protocol contract, then first client

Treat a generic NIP-46 client (NDK in tests) as the signer harness (`nostrconnect` first, `bunker://` fallback, NIP-44, `sign_event:13`, permission list on `connect`). Bitspark is the first real client, not the proof that the signer works.

Add a **Mode B** product smoke after the signer bar is green: public (or `npm run preview`) Bitspark in a browser that is *not* pretending to be on localhost-only relay, signer on another host/port, pairing via URI, approve in signer UI.

Keep nsecbunkerd around as a known-strict interop target so we do not invent a dialect.

### 3. Thin signer, own UI

New small daemon (new git root — decided in CONTRACT):

- one encrypted key
- NIP-46 over configured relays
- local first-run UI: create/import, backup, pending approvals, connected clients, relay settings

Pairing happy path is `nostrconnect` + in-app approve. No Prisma `User` for `username@domain` unless we later need a web password for non-Umbrel clients.

### 4. Relays as configuration

- Compose/Umbrel: local relay service, ephemeral or explicit volume (decide: clean-each-run vs persist marketplace events — signing mailbox vs Bitspark data may differ).
- Profile/settings: local default; add client-reachable URL for Mode B (node LAN IP, Tor, or a public relay).
- Never force users onto local-only if they set another relay.

### 5. Umbrel packaging

Two apps that can install independently:

- Signer (this)
- Bitspark (existing SPA)

Same-node config injection for Mode A (how Bitspark finds the mailbox/UI on the box) is part of the product layer, not a NIP-46 extension. If injection is missing, URI paste still works.

### 6. Only then: multi-user / hosted

When the signer bar is green (one identity + client ACL, NIP-46 over a mailbox) and product Modes A and B work:

- multiple keys in one install (household)
- Mode C only with an explicit custody decision and admin/ops story we own (not `app.nsecbunker.com`)

## Open questions

Decided in [CONTRACT.md](./CONTRACT.md): new repo; relays are config (no hosted mailbox); in-app approve; mailbox key hidden; hosted keys out indefinitely.

**Still open:** unlock after reboot — auto-unlock (`wrap.key` on the volume) vs user passphrase (real encryption, signing needs the UI after every restart). Working assumption is auto-unlock for Umbrel enablement. Alternative, implications, and leftover B details: [ARCHITECTURE.md](./ARCHITECTURE.md) §6.

## Related material in this repo

- Product: [PRODUCT.md](./PRODUCT.md)
- Contract: [CONTRACT.md](./CONTRACT.md)
- Architecture: [ARCHITECTURE.md](./ARCHITECTURE.md)
- How this document was decided: [Signer product decisions](../workflows/signer-product-decisions.md)
- [SETUP-CONCEPTS.md](../../SETUP-CONCEPTS.md) — identities and why nsecbunkerd is split the way it is (useful as negative space).
- [SETUP-GUIDE.md](../../SETUP-GUIDE.md) — current Docker/make bunker (not the Umbrel product).
- Local relay work in Compose / `PROFILE=local` — keep the *idea*, not necessarily the nsecbunkerd wiring.
