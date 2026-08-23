# nsecbunkerd
Daemon to remotely sign nostr events using keys.

For a step-by-step Docker walkthrough, follow the [Quickstart (SETUP-GUIDE.md)](./SETUP-GUIDE.md).
For the concepts behind it — the signing identity, bunker identity, admin identity, the one-time key
import step, and advanced/production configuration — see [SETUP-CONCEPTS.md](./SETUP-CONCEPTS.md).

## Easy setup via make

The `make` targets wrap the whole Docker flow. From the repo root:

```shell
make build     # build the local image (first time only)
make keygen    # generate a signing identity — SAVE the printed nsec
make setup     # guided setup: import key, configure, start, create web-auth user
```

`make setup` prompts for the few secrets it needs (admin npub, encryption passphrase, signing nsec,
web-auth password) and prints your connection strings at the end. For the full walkthrough,
non-interactive usage, and isolated `local` test stacks, see the
[Quickstart (SETUP-GUIDE.md)](./SETUP-GUIDE.md).

### Daily use (already configured)

If you completed setup once, you only need to start and stop the stack:

```shell
make up          # start (default profile, port 3009)
make down        # stop
make connection  # print bunker:// URIs again
```

Use `PROFILE=local` for a second isolated stack (port 3019). For arbitrary disposable stacks on
new PCs or for testing, use `make profile-setup NAME=<name>`. See
[SETUP-GUIDE.md — Already set up?](./SETUP-GUIDE.md#already-set-up-daily-use) for profiles, ports,
and the full command list.

### Get connection strings

```shell
make connection
# or directly:
docker compose exec nsecbunkerd cat /app/config/connection.txt        # NIP-46 signing clients
docker compose exec nsecbunkerd cat /app/config/admin-connection.txt  # admin / app.nsecbunker.com
```

nsecBunker will give you a connection string like (NIP-46 `bunker://<hex>?relay=…`):

```
bunker://<64-hex-remote-signer-pubkey>?relay=wss%3A%2F%2Frelay.example.com%2F
```

You can visit https://app.nsecbunker.com/ to administrate your nsecBunker remotely, or explore `nsecbunkerd`'s CLI
to find the options to add and approve keys from the CLI.

## Hard setup:
(If you installed via docker you don't need to do any of this, skip to the [Configure](#configure) section)

Node.js v18 or newer is required.

```shell
git clone <nsecbunkerd-repo>
npm i
npm run build
npx prisma migrate deploy
```

## Configure

### Easy: Remote configuration

Using the connection string you saw before, you can go to https://app.nsecbunker.com and paste your connection string.

Note that ONLY the npub that you designated as an administrator when launching nsecBunker is able to control your nsecBunker. Even if someone sees your connection string, without access to your administrator keys, there's nothing they can do.

### Hard: manual configuration

(If you are using remote configuration you don't need to do any of this)

### Add your nsec to nsecBunker

Here you'll give nsecBunker your nsec. It will ask you for a passphrase to encrypt it on-disk.
The name is an internal name you'll use to refer to this keypair. Choose anything that is useful to you.

```shell
npm run nsecbunkerd -- add --name <your-key-name>
```

#### Example

```bash
$ npm run nsecbunkerd -- add --name "Uncomfortable family"

nsecBunker uses a passphrase to encrypt your nsec when stored on-disk.
Every time you restart it, you will need to type in this password.

Enter a passphrase: <enter-your-passphrase-here>
Enter the nsec for Uncomfortable family: <copy-your-nsec-here>
nsecBunker generated an admin password for you:

***************************

You will need this to manage users of your keys.
````

## Start

```bash
$ npm run lfg --admin <your-admin-npub>
```

## Testing with `nsecbunker-client`

nsecbunker ships with a simple client that can request signatures from an nsecbunkerd:

```bash
nsecbunker-client sign <target-npub> "hi, I'm signing from the command line with my nsecbunkerd!"
```

## OAuth-like provider

nsecBunker can run as an OAuth-like provider, which means it will allow new users to create accounts remotely from any compatible client.

To enable this you'll need to configure a few things on your `nsecbunker.json` config file. In addition to the normal configuration:

```json
{
    "baseUrl": "https://....", // a public URL where this nsecBunker can be reached via HTTPS
    "authPort": 3000, // Port number where the OAuth-like provider will listen
    "domains": {
        "your-domain-here": {
            "nip05": "/your-nip05-nostr.json-file", // The location where NIP-05 entries to your domain are stored

            "nip89": {
                "profile": { // a kind:0-like profile
                    "name": "my cool nsecbunker instance", // The name of your nsecBunker instance
                    "about": "...",
                },
                "operator": "npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft", // (optional) npub of the operator of this nsecbunker
                "relays": [ // list of relays where to publush the nip89 announcement
                    "https://relay.damus.io",
                    "https://pyramid.fiatjaf.com"
                ]
            }

            // Wallet configuration (optional)
            "wallet": {
                "lnbits": {
                    "url": "https://legend.lnbits.com", // The URL where your LNbits instance is running
                    "key": "your-lnbits-admin-key", // The admin key for your LNbits instance
                    "nostdressUrl": "http://localhost:5556" // The URL where your nostdress instance is running
                }
            }
        }
    }
}
```

With this configuration users will be able to:

* create a new key managed by your nsecbunker
* get an lnbits-based LN wallet
* get zapping capabilitiyes through nostdress

For this to work you'll need to run, in addition to `nsecbunkerd`, an lnbits instance and a [nostdress](https://github.com/believethehype/nostdress) instance. Your LNBits **needs to have the user manager extension enabled**.

- [ ] TODO: Add NWC support

When booting up, the nsecbunkerd will publish a NIP-89 announcement (`kind:31990`), which is the way clients find out about your nsecbunker.

When a bunker provides a wallet and zapping service (`wallet` and `nostdressUrl` are configured), it will add tags:
```json
{
    "tags": [
        [ "f", "wallet" ],
        [ "f", "zaps" ]
    ]
}
```

# Authors

* [pablof7z](nostr:npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft)
    * npub1l2vyh47mk2p0qlsku7hg0vn29faehy9hy34ygaclpn66ukqp3afqutajft

# License

MIT