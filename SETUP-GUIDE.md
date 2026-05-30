# nsecBunker Quickstart (Docker + make)

A working local nsecBunker in three commands. The `make` targets wrap all the Docker steps; you only
provide three secrets when prompted (encryption passphrase, signing `nsec`, web-auth password).

Want to understand the moving parts (the three identities, where each setting is read, advanced and
production setups)? See [SETUP-CONCEPTS.md](./SETUP-CONCEPTS.md).

> Don't commit `.env`, `signer-identity.txt`, `nsecbunker.json`, `connection.txt`, or
> `admin-connection.txt`. They contain secrets (all are gitignored).

## Prerequisites

- Docker and Docker Compose.
- A terminal in the repo root (next to `Makefile` / `docker-compose.yml`).

## TL;DR

```shell
make build                 # build the local image (first time only)
make keygen                # generate a signing identity — SAVE the printed nsec
make setup                 # guided setup: imports the key, configures, starts, creates web-auth user
```

That's it. `make setup` prints your connection strings at the end.

## Step by step

### 1. Build the image (first run only)

```shell
make build
```

### 2. Generate a signing identity

```shell
make keygen
```

This prints, once:

```text
nsec=nsec1...
npub=npub1...
pubkey_hex=...
```

**Save the `nsec` in your password manager now** — it is the private key and is not written to disk.
By default keys are generated with Node's built-in crypto (generic, not nostr-specific). To use
nostr-tools instead:

```shell
make keygen KEYGEN=nostr
```

If you already have an `nsec` you want to protect, skip this step and paste it during `make setup`.

### 3. Run the guided setup

```shell
make setup
```

You'll be prompted for (unless provided as env vars):

- **Admin npub** — the identity allowed to manage the bunker (`npub1...`).
- **Encryption passphrase** — encrypts the signing key on disk (stored in `signer-identity.txt`).
- **Signing nsec** — the `nsec` from step 2 (or your existing one).
- **Web auth password** — protects the browser approval page.

`make setup` then: writes `.env`, imports the signing key (creating `nsecbunker.json` with an
auto-generated bunker key), sets relays + web-auth config, starts the stack, waits for startup, and
creates the local web-auth user. It finishes by printing your connection strings.

### 4. Verify

```shell
make connection
```

You're done when:

- `connection.txt` shows a `bunker://<hex>?relay=...` URI (use it with signing clients).
- `admin-connection.txt` shows the admin URI (use it with `app.nsecbunker.com`).
- Approval requests appear at `http://localhost:3009/requests/<request-id>` (log in with the
  web-auth password). For `PROFILE=local` the port is `3019`.

## Fully non-interactive

Pass the secrets as environment variables to skip all prompts (useful for automation):

```shell
ADMIN_NPUBS=npub1... \
PASSPHRASE='long-random-passphrase' \
NSEC=nsec1... \
WEB_AUTH_PASSWORD='web-auth-password' \
make setup
```

## Profiles and overrides

`make` uses *profiles* — preset bundles you can still override per knob.

```shell
make setup                       # default profile (dir ~/.nsecbunker-config, port 3009)
make setup PROFILE=local         # isolated test stack (dir ~/.nsecbunker-config-local, port 3019)
make setup PROFILE=local HOST_PORT=4000 KEY_NAME=test@local RELAY=wss://relay.damus.io
```

With `PROFILE=local`, Compose also starts a **local Nostr relay** at `ws://localhost:7777`
(`nostr-rs-relay`, no persisted events between runs). `make setup PROFILE=local` points
`config.nostr.relays` at that relay by default.

Because each profile uses its own config dir, host port, and Compose project name, `default` and
`local` can run **at the same time** without interfering. Run `make help` to see the active profile
and all knobs.

## Managing the stack

```shell
make up            # start
make down          # stop
make restart       # restart
make logs          # follow logs
make ps            # status
make connection    # print connection strings
make relay-smoke   # publish + read back on the local relay (PROFILE=local; runs in Docker)
make teardown      # stop and (after confirmation) remove this profile's config dir
```

`teardown` is profile-scoped, so wiping `local` never touches `default` — handy for repeatable
clean-room testing.

## Troubleshooting

- **`Cannot read properties of undefined (reading 'iv')` on startup** — `make down && make up` (or
  `docker compose up -d --force-recreate`) so Compose re-reads `.env`.
- **`Remote signer rejected this client`** — approve the client from the `/requests/<id>` page, or
  from the admin UI using `admin-connection.txt`.
- **No `/requests/<id>` page / logs show `baseUrl undefined`** — re-run `make setup`; it sets
  `baseUrl`/`authPort`/`authHost` in `nsecbunker.json`.
- **Prisma `Error code 14: Unable to open the database file`** — `DATABASE_URL` is fixed in
  `docker-compose.yml` to `file:/app/config/nsecbunker.db`; don't override it in `.env` for Docker.

For deeper explanations and more gotchas, see [SETUP-CONCEPTS.md](./SETUP-CONCEPTS.md).
