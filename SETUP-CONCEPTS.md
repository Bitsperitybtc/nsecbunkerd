# nsecBunker Concepts & Reference

This document explains the *why* behind the nsecBunker setup: the identities involved, what
"management" means, advanced configuration, and the common gotchas.

If you just want to get a local bunker running, start with the step-by-step
[SETUP-GUIDE.md](./SETUP-GUIDE.md) instead and come back here when something needs explaining.

## The Three Identities

nsecBunker uses more than one Nostr identity. Keeping them separate makes the setup easier to
reason about.

### 1. Signing Identity

This is the Nostr identity you want nsecBunker to protect and sign as.

It has:

```text
nsec=...
npub=...
pubkey_hex=...
```

The `nsec` is the private key. nsecBunker stores it encrypted in `nsecbunker.json` and unlocks it
on startup with a passphrase.

When a NIP-46 client asks the bunker to sign an event, this is the identity that produces the
signature.

### 2. Bunker Communication Identity

This is nsecBunker's own identity. Clients communicate with this identity over Nostr relays.

You normally do not create this key manually. nsecBunker generates it when the config is created
and stores it in:

```text
$HOME/.nsecbunker-config/nsecbunker.json
```

The useful output from this key is written to:

```text
$HOME/.nsecbunker-config/connection.txt
$HOME/.nsecbunker-config/admin-connection.txt
```

Use `connection.txt` for signing clients. Use `admin-connection.txt` for the remote admin UI.

### 3. Admin Identity

This is your own Nostr public key, configured with `ADMIN_NPUBS`.

It answers the question: who is allowed to manage this bunker?

It does not have to be the same as the signing identity. For example:

```text
signing identity = company-key@example.com
admin identity   = your personal Nostr npub
```

For a local test setup, you can use the same Nostr identity for both, but production setups should
keep them separate.

## How Configuration Is Split

Configuration lives in a few places, and each one is read differently:

| Source | Read by | Controls |
| --- | --- | --- |
| `docker-compose.yml` (`environment:`) | Docker Compose | `DATABASE_URL` — a **constant** (`file:/app/config/nsecbunker.db`) for Docker |
| `.env` | Docker Compose | `ADMIN_NPUBS`, `NSECBUNKER_KEY_NAME` |
| `profiles/<name>.env` | `make` (included Makefile fragment) | Per-identity defaults: config dir, ports, relay URLs, signer file — no secrets |
| Shell env via `make` | Compose interpolation | `NSECBUNKER_CONFIG_DIR`, `NSECBUNKER_HOST_PORT`, `COMPOSE_PROJECT_NAME`, `SIGNER_IDENTITY_FILE` (from active profile) |
| `signer-identity*.txt` | The Docker entrypoint (as a secret) | Only the `encryption_passphrase` line, to unlock the key on startup (one file per profile) |
| `nsecbunker.json` | nsecBunker itself | `nostr.relays`, `nostr.clientRelays`, `admin.adminRelays`, `admin.clientRelays`, `baseUrl`, `authPort`, generated `admin.key`, encrypted keys |

Key consequences of this split:

- `DATABASE_URL` is **not** a user knob for Docker. The DB always lives on the mounted
  `/app/config` volume, so the container path is fixed in `docker-compose.yml`. Only override it (in
  `.env`) if you run nsecbunkerd directly on the host.
- `.env` does **not** override `nostr.relays`, `admin.adminRelays`, `baseUrl`, or `authPort`. Those
  live in `nsecbunker.json` (and `make setup` writes them for you).
- `signer-identity.txt` does **not** import the `nsec`. It only supplies the startup passphrase.
  The `nsec` itself is imported once with the `add` command (which `make setup` runs).
- `NSECBUNKER_KEY_NAME` (in `.env`) must exactly match the name passed to `add --name`.

### Where the config directory lives

The host directory mounted at `/app/config` is parameterizable via `NSECBUNKER_CONFIG_DIR` (default
`$HOME/.nsecbunker-config`). The app derives all its outputs — `connection.txt`,
`admin-connection.txt`, the SQLite DB — from that one mounted directory, so pointing it elsewhere is
enough to run fully isolated stacks. Profile files in `profiles/*.env` set these knobs per identity;
`PROFILE=local` uses `$HOME/.nsecbunker-config-local`, port `3019`, and `signer-identity-local.txt`,
so it can run alongside the default stack.

### Generating the signing key

The signing key is a standard secp256k1/Schnorr key; `nsec`/`npub` are just bech32 encodings.
`make keygen` generates it **inside the container** in one of two ways:

- `KEYGEN=generic` (default): Node's built-in crypto for the key, plus a self-contained bech32
  encoder. No nostr-tools dependency.
- `KEYGEN=nostr`: the `nostr-tools` `generateSecretKey`/`getPublicKey` path.

The generated `nsec` is printed once and never written to disk — store it in your password manager.

## Relays

The bunker and your browser often need **different relay URLs** when nsecBunker runs in Docker:

| Config field | Who dials it | Typical `PROFILE=local` value |
| --- | --- | --- |
| `nostr.relays` / `admin.adminRelays` | The bunker container (NDK) | `ws://relay:8080` (Docker network) |
| `nostr.clientRelays` / `admin.clientRelays` | Browser / Bitspark (in `connection.txt`) | `ws://<host-ip>:7777` |
| `baseUrl` | Browser approval page | `http://<host-ip>:3019` |

When `clientRelays` is omitted, `connection.txt` falls back to `nostr.relays` (fine for a public
relay like `wss://nos.lol`, wrong for `ws://relay:8080`).

`make setup` and `make patch-config` write these from the active profile's `RELAY`, `CLIENT_RELAY`,
and `PUBLIC_BASE_URL` (see `profiles/local.env` and `DEV_HOST`).

`app.nsecbunker.com` in logs is a UI label, not a relay URL.

## What Management Means

Management means controlling the bunker, not signing as the protected identity.

Admin actions include:

- Approving clients that request signing access.
- Listing keys and connected users.
- Unlocking or creating keys.
- Revoking user access.
- Creating policies or tokens.
- Managing the bunker through `app.nsecbunker.com`.

Only identities listed in `ADMIN_NPUBS` can perform these actions.

## Web Auth vs. Encryption Passphrase

There are two different secrets, and they are easy to confuse:

- `encryption_passphrase` (in `signer-identity.txt`): unlocks the signing `nsec` on startup.
- The **web auth password**: protects the browser approval page at `/requests/<request-id>`.

They are unrelated. `make setup` creates the web auth user for you.

`signer-identity.txt` is a **passphrase-only secret** — its single functional line is
`encryption_passphrase=...` (the only line the entrypoint reads). It deliberately holds nothing else:
the `npub`/`pubkey_hex` are non-secret and derivable from `connection.txt` at any time, and the one
thing that truly needs backup — the signing `nsec` — is printed once by `make keygen` and should be
stored in your own password manager rather than persisted in the repo.

The web auth user record uses:

- `username` / `domain` — derived from the key name. For `bitspark@local`, that is
  `username=bitspark`, `domain=local`.
- `pubkey` — the **signing identity** public key (the hex value after `bunker://` in
  `connection.txt`), *not* the admin/bunker pubkey from `admin-connection.txt`.

In a connection URI like this:

```text
bunker://e7abf54f82800a396a363988cb56304cda7d140a36e2b08ef2ac6bf3dede12e0?relay=wss%3A%2F%2Fnos.lol
```

the signing identity pubkey is the hex value after `bunker://`:

```text
e7abf54f82800a396a363988cb56304cda7d140a36e2b08ef2ac6bf3dede12e0
```

## Advanced Configuration

### Browser approval pages (web auth)

To use browser-based approval pages, add top-level web auth settings to `nsecbunker.json`:

```json
{
  "baseUrl": "http://localhost:3009",
  "authPort": 3000,
  "authHost": "0.0.0.0"
}
```

- `baseUrl` is the URL sent to clients, for example
  `http://localhost:3009/requests/<request-id>`.
- `authPort` is the port nsecBunker listens on **inside** the container.
- The **host** port in `docker-compose.yml` must match the port in `baseUrl`.

The shipped `docker-compose.yml` maps host port `3009` to container port `3000`:

```yaml
ports:
  - "3009:3000"
```

So `baseUrl` should use `3009` and `authPort` should be `3000`. If you prefer the browser URL to use
`3000`, change both the mapping (`"3000:3000"`) and `baseUrl` to match.

### Separate signing and admin identities (production)

For production, set `ADMIN_NPUBS` to your personal npub and use a different signing identity for the
key being protected. The local quickstart uses the same identity for both only to keep things simple.

## Common Gotchas

- `signer-identity.txt` does not import the `nsec`. It only supplies the startup passphrase.
- `NSECBUNKER_KEY_NAME` must match the name passed to `add --name`.
- If `NSECBUNKER_KEY_NAME` looks correct but startup says
  `Cannot read properties of undefined (reading 'iv')`, recreate the container so Compose re-reads
  `.env` (`docker compose up -d --force-recreate`).
- For Docker, `DATABASE_URL` is fixed in `docker-compose.yml` to `file:/app/config/nsecbunker.db`.
  Don't set it in `.env` for Docker — a host path can cause Prisma
  `Error code 14: Unable to open the database file`, because `$HOME` inside the container is not your
  host home directory.
- Relay settings are read from `nsecbunker.json` on the mounted config volume, not `.env`. Re-apply
  profile values with `make patch-config PROFILE=<name>`.
- `nostr.clientRelays` (or `nostr.relays` when omitted) controls relays in `connection.txt`;
  `admin.clientRelays` (or `admin.adminRelays`) controls `admin-connection.txt`. The bunker itself
  always dials `nostr.relays` / `admin.adminRelays`.
- With a Docker relay, do **not** put `ws://localhost:7777` in `nostr.relays` — inside the container
  `localhost` is the container, not your host. Use `ws://relay:8080` for the bunker and
  `CLIENT_RELAY=ws://<host-ip>:7777` for clients.
- `app.nsecbunker.com` in logs is a UI label, not a relay URL.
- If logs show `baseUrl undefined`, nsecBunker will not create a `/requests/<id>` browser approval
  page. It will ask the admin over Nostr instead.
- If a client reports `Remote signer rejected this client`, approve it either from the generated
  `/requests/<id>` page or from the admin UI using `admin-connection.txt`.
- The generated authorization page is per request. It looks like
  `http://localhost:3009/requests/<request-id>` when `baseUrl` is configured.
- `ADMIN_NPUBS` is the manager identity, not necessarily the identity being signed as.
- The bunker communication key is generated automatically and stored in `nsecbunker.json`.
- Do not commit `.env`, `signer-identity.txt`, `nsecbunker.json`, `connection.txt`, or
  `admin-connection.txt`.
