# nsecBunker Setup Guide

This guide explains the Docker setup flow and the different identities involved in a fresh nsecBunker installation.

## The Three Identities

nsecBunker uses more than one Nostr identity. Keeping them separate makes the setup easier to reason about.

### 1. Signing Identity

This is the Nostr identity you want nsecBunker to protect and sign as.

It has:

```text
nsec=...
npub=...
pubkey_hex=...
```

The `nsec` is the private key. nsecBunker stores it encrypted in `nsecbunker.json` and unlocks it on startup with a passphrase.

When a NIP-46 client asks the bunker to sign an event, this is the identity that produces the signature.

### 2. Bunker Communication Identity

This is nsecBunker's own identity. Clients communicate with this identity over Nostr relays.

You normally do not create this key manually. nsecBunker generates it when the config is created and stores it in:

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

For a local test setup, you can use the same Nostr identity for both, but production setups should keep them separate.

## Fresh Docker Setup

### 1. Prepare the Config Directory

```shell
mkdir -p "$HOME/.nsecbunker-config"
cp .env.example .env
```

For Docker Compose, `.env` should use the container path for SQLite:

```text
DATABASE_URL="file:/app/config/nsecbunker.db"
```

### 2. Choose or Generate a Signing Identity

If you already have a Nostr identity you want the bunker to sign as, use its `nsec`.

If you want a completely new identity, generate one:

```shell
node --input-type=module -e "import { generateSecretKey, getPublicKey, nip19 } from 'nostr-tools'; const sk = generateSecretKey(); const pk = getPublicKey(sk); console.log('nsec=' + nip19.nsecEncode(sk)); console.log('npub=' + nip19.npubEncode(pk)); console.log('pubkey_hex=' + pk);"
```

Save the generated `nsec` somewhere safe while you complete setup. It is a private key.

### 3. Choose a Key Name and Passphrase

The key name is an internal label used by nsecBunker. It can be anything meaningful:

```text
wild@leaf
company@signer
bitspark@local
```

The passphrase encrypts the signing `nsec` on disk. You will use the same passphrase in two places:

- When running the `add` command.
- In `signer-identity.txt`, so Docker can unlock the key on startup.

Create `signer-identity.txt` next to `docker-compose.yml`:

```text
# nsecbunkerd local signer identity
# DO NOT COMMIT OR SHARE THIS FILE.
key_name=wild@leaf
npub=npub1...
nsec=nsec1...
pubkey_hex=...
encryption_passphrase=your-long-random-passphrase
```

Only `encryption_passphrase` is read by Docker. The other lines are for your notes and recovery workflow.

### 4. Configure `.env`

Set the signing key name:

```text
NSECBUNKER_KEY_NAME=wild@leaf
```

Set your admin identity:

```text
ADMIN_NPUBS=npub1youradminnpub...
```

`ADMIN_NPUBS` should be an identity you control in a Nostr client. It is allowed to manage the bunker.

For Docker Compose, keep the SQLite path inside the mounted container directory:

```text
DATABASE_URL="file:/app/config/nsecbunker.db"
```

Do not use a host path such as `$HOME/.nsecbunker-config/nsecbunker.db` in `.env` for Docker. Compose passes that value into the container, where `$HOME` is not your host home directory.

### 5. Configure Relays and Web Authorization

Most runtime settings live in:

```text
$HOME/.nsecbunker-config/nsecbunker.json
```

This file is mounted into the container as:

```text
/app/config/nsecbunker.json
```

`.env` does not override `nostr.relays`, `admin.adminRelays`, `baseUrl`, or `authPort`.

Set the signing/client relays and admin relays in `nsecbunker.json`:

```json
{
  "nostr": {
    "relays": ["wss://nos.lol"]
  },
  "admin": {
    "adminRelays": ["wss://nos.lol"]
  }
}
```

`nostr.relays` are used for the NIP-46 signing connection written to `connection.txt`.

`admin.adminRelays` are used for the admin RPC connection written to `admin-connection.txt`.

To use browser-based approval pages, add top-level web auth settings:

```json
{
  "baseUrl": "http://localhost:3000",
  "authPort": 3000,
  "authHost": "0.0.0.0"
}
```

`baseUrl` is the URL sent to clients, for example:

```text
http://localhost:3000/requests/<request-id>
```

`authPort` is the port nsecBunker listens on inside the container. The host port in `docker-compose.yml` must match the port in `baseUrl`:

```yaml
ports:
  - "3000:3000"
```

If you want the browser URL to use port `3009`, use:

```json
{
  "baseUrl": "http://localhost:3009",
  "authPort": 3000,
  "authHost": "0.0.0.0"
}
```

and expose the container as:

```yaml
ports:
  - "3009:3000"
```

### 6. Import the Signing Key

This is the step that actually stores the signing `nsec` in nsecBunker.

Run it inside the Docker image:

```shell
docker compose run --rm --entrypoint "" nsecbunkerd \
  node ./dist/index.js add \
  --config /app/config/nsecbunker.json \
  --name wild@leaf
```

When prompted:

```text
Enter a passphrase:
Enter the nsec for wild@leaf:
```

Enter the same passphrase from `signer-identity.txt`, then enter the signing identity's `nsec`.

This writes the encrypted key into:

```text
$HOME/.nsecbunker-config/nsecbunker.json
```

The plaintext `nsec` is not read from `signer-identity.txt` by the Docker entrypoint.

### 7. Create the Local Web Auth User

The browser approval page at `/requests/<request-id>` asks for a web auth password. This is separate from the `encryption_passphrase` in `signer-identity.txt`.

For a key name like `wild@leaf`, the web auth record uses:

```text
username=wild
domain=leaf
```

The `pubkey` in this record is the signing identity public key. You can get it from either:

- the `pubkey_hex=` line in `signer-identity.txt`, if present
- the generated `connection.txt` URI after startup

In a connection URI like this:

```text
bunker://e7abf54f82800a396a363988cb56304cda7d140a36e2b08ef2ac6bf3dede12e0?relay=wss%3A%2F%2Fnos.lol
```

the signing identity pubkey is the hex value after `bunker://`:

```text
e7abf54f82800a396a363988cb56304cda7d140a36e2b08ef2ac6bf3dede12e0
```

Create or update the web auth user with a password you choose:

```shell
read -s -p "Choose web auth password for wild@leaf: " WEB_AUTH_PASSWORD
echo

docker compose exec -T -e WEB_AUTH_PASSWORD="$WEB_AUTH_PASSWORD" nsecbunkerd node --input-type=module <<'EOF'
import bcrypt from 'bcrypt';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const username = 'wild';
const domain = 'leaf';
const password = process.env.WEB_AUTH_PASSWORD;
const pubkey = 'replace-with-signing-identity-pubkey-hex';

if (!password) throw new Error('WEB_AUTH_PASSWORD is missing');
if (!pubkey || pubkey.startsWith('replace-with-')) throw new Error('Set pubkey to the signing identity pubkey hex');

const hashed = await bcrypt.hash(password, 10);

await prisma.user.upsert({
  where: { username },
  update: { domain, password: hashed, pubkey, email: '' },
  create: { username, domain, password: hashed, pubkey, email: '' },
});

console.log(`Created/updated web auth user ${username}@${domain}`);
await prisma.$disconnect();
EOF
```

Do not use the admin connection pubkey here. The admin/bunker management pubkey appears in `admin-connection.txt`; the web auth `User.pubkey` should be the protected signing identity pubkey from `connection.txt` or `signer-identity.txt`.

### 8. Start nsecBunker

```shell
docker compose up -d
```

The entrypoint reads `encryption_passphrase` from the Docker secret and starts:

```text
node ./dist/index.js start --verbose --key "$NSECBUNKER_KEY_NAME"
```

After startup, get the connection strings:

```shell
docker compose exec nsecbunkerd cat /app/config/connection.txt
docker compose exec nsecbunkerd cat /app/config/admin-connection.txt
```

Use `connection.txt` with signing clients. Use `admin-connection.txt` with the admin UI.

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

## Common Gotchas

- `signer-identity.txt` does not import the `nsec`. It only supplies the startup passphrase.
- `NSECBUNKER_KEY_NAME` must match the name passed to `add --name`.
- If `NSECBUNKER_KEY_NAME` looks correct but startup says `Cannot read properties of undefined (reading 'iv')`, recreate the container so Compose re-reads `.env`.
- For Docker, `DATABASE_URL` should be `file:/app/config/nsecbunker.db`. A host path can cause Prisma `Error code 14: Unable to open the database file`.
- Relay settings are read from `$HOME/.nsecbunker-config/nsecbunker.json`, not `.env`.
- `nostr.relays` controls the client signing connection; `admin.adminRelays` controls the admin RPC connection.
- `app.nsecbunker.com` in logs is a UI label, not a relay URL.
- If logs show `baseUrl undefined`, nsecBunker will not create a `/requests/<id>` browser approval page. It will ask the admin over Nostr instead.
- If Bitspark reports `Remote signer rejected this client`, approve the browser/client either from the generated `/requests/<id>` page or from the admin UI using `admin-connection.txt`.
- The generated authorization page is per request. It looks like `http://localhost:3000/requests/<request-id>` when `baseUrl` is configured.
- `ADMIN_NPUBS` is the manager identity, not necessarily the identity being signed as.
- The bunker communication key is generated automatically and stored in `nsecbunker.json`.
- Do not commit `.env`, `signer-identity.txt`, `nsecbunker.json`, `connection.txt`, or `admin-connection.txt`.
