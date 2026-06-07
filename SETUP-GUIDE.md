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

## Already set up? (daily use)

If you ran `make setup` before, you do **not** need to run `make build`, `make keygen`, or
`make setup` again unless you want a clean slate or something is broken.

Setup is one-time per profile. Encrypted keys, the SQLite database, and connection strings live
under `~/.nsecbunker-config` (default) or `~/.nsecbunker-config-local` (`PROFILE=local`). The repo
holds `.env` and `signer-identity.txt` for Docker.

From the repo root, day to day:

```shell
make up              # start the default stack (port 3009)
make ps              # check it's running
make connection      # print bunker:// connection strings again
make down            # stop
```

For a second stack you created with `PROFILE=local` (port 3019):

```shell
make up PROFILE=local
make ps PROFILE=local
make connection PROFILE=local
make down PROFILE=local
```

Both profiles can run at the same time — each has its own config dir, host port, and Docker project
name. Run `make help` to see the active profile and all knobs.

Containers use `restart: unless-stopped`, so they may already be running after a reboot if Docker is
up. Check with `make ps` before starting again.

See [Managing the stack](#managing-the-stack) for logs, restart, and teardown.

## TL;DR (first-time setup)

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

A **profile** is a config-file bundle in `profiles/<name>.env`. Pick one with `PROFILE=<name>`
(defaults to `default`); every variable can still be overridden on the CLI.

```shell
make setup                       # profile `default` (dir ~/.nsecbunker-config, port 3009)
make setup PROFILE=local         # profile `local`   (dir ~/.nsecbunker-config-local, port 3019)
make setup PROFILE=local HOST_PORT=4000 KEY_NAME=test@local RELAY=wss://relay.damus.io
```

Each profile file (safe to commit — it holds no secrets) sets:

| Variable | Meaning |
| --- | --- |
| `CONFIG_DIR` | Host dir mounted at `/app/config` (keys, DB, connection files) |
| `PROJECT` | Docker Compose project name (keeps stacks isolated) |
| `HOST_PORT` | Host port published for the approval HTTP server (maps to container `:3000`) |
| `KEY_NAME` | Signing key name (`name@domain`) to unlock on start |
| `RELAY` | Relay the **bunker** dials (`nostr.relays` / `admin.adminRelays`) |
| `CLIENT_RELAY` | Relay in **`connection.txt`** — must be reachable from **your browser** (optional; defaults to `RELAY`) |
| `PUBLIC_BASE_URL` | Approval page base URL sent to clients, e.g. `http://127.0.0.1:3019` (optional; defaults to `http://localhost:HOST_PORT`) |
| `SIGNER_IDENTITY_FILE` | Per-profile passphrase file (gitignored) that unlocks the keys |
| `LOCAL_RELAY` | `1` to also start the bundled `nostr-rs-relay` container |
| `RELAY_HOST_PORT` | Host port published for the relay container (default `7777`) |

Because each profile uses its own config dir, host port, Compose project name, **and signer file**,
profiles can run **at the same time** without interfering. Run `make help` to list available
profiles and show the active one's resolved values.

### Add another identity

Copy an existing profile and adjust the isolating knobs:

```shell
cp profiles/local.env profiles/dev.env
# edit profiles/dev.env: CONFIG_DIR, PROJECT, HOST_PORT, KEY_NAME, SIGNER_IDENTITY_FILE
make setup PROFILE=dev
make up   PROFILE=dev
```

`SIGNER_IDENTITY_FILE` lets each identity use its **own encryption passphrase**. `make setup`
creates the file if missing (prompting for the passphrase) or reuses it if present.

### Local relay and client-facing URLs

When `LOCAL_RELAY=1` (the `local` profile), Compose starts **nostr-rs-relay** on the host at port
`7777`. The bunker uses `RELAY=ws://relay:8080` (Docker network). Your browser uses
`CLIENT_RELAY` and `PUBLIC_BASE_URL` — set via `DEV_HOST` in `profiles/local.env` (default: the
host's LAN IP). No SSH forwarding needed if your browser can reach that IP.

```shell
make patch-config PROFILE=local DEV_HOST=172.29.105.70   # if the IP changes
make connection PROFILE=local
```

| Setting | Example | Used by |
| --- | --- | --- |
| `RELAY` | `ws://relay:8080` | Bunker container |
| `CLIENT_RELAY` | `ws://172.29.105.70:7777` | `connection.txt` → browser |
| `PUBLIC_BASE_URL` | `http://172.29.105.70:3019` | Approval page in browser |

Use `127.0.0.1` in `DEV_HOST` only when you tunnel ports over SSH from another machine.

## Managing the stack

These are the commands you use after the one-time setup. Pass `PROFILE=local` when managing the
local test stack (same as in [Already set up?](#already-set-up-daily-use)).

```shell
make up            # start
make down          # stop
make restart       # restart
make logs          # follow logs
make ps            # status
make connection    # print connection strings
make patch-config  # re-apply RELAY / CLIENT_RELAY / PUBLIC_BASE_URL from profile
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
- **Forgot the web auth password** (browser page at `/requests/<id>`) — set a new one without
  re-running setup: `WEB_AUTH_PASSWORD='new-password' make web-auth-password` (or `make
  web-auth-password` to be prompted). Use `PROFILE=local` if that stack uses port 3019. Log in as
  `<username>@<domain>` from `NSECBUNKER_KEY_NAME` in `.env` (e.g. `bitspark@local`).

For deeper explanations and more gotchas, see [SETUP-CONCEPTS.md](./SETUP-CONCEPTS.md).
