// Patch relay + web-auth settings into an existing nsecbunker.json without
// disturbing generated values (e.g. admin.key). Runs inside the container.
//
// Env:
//   NSECBUNKER_RELAY      (default wss://nos.lol)
//   NSECBUNKER_HOST_PORT  (default 3009) -> used for baseUrl
import { readFileSync, writeFileSync } from 'node:fs';

const path = '/app/config/nsecbunker.json';
const relay = process.env.NSECBUNKER_RELAY || 'wss://nos.lol';
const port = process.env.NSECBUNKER_HOST_PORT || '3009';

const cfg = JSON.parse(readFileSync(path, 'utf8'));

cfg.nostr = cfg.nostr || {};
cfg.nostr.relays = [relay];

cfg.admin = cfg.admin || {};
cfg.admin.adminRelays = [relay];

cfg.baseUrl = `http://localhost:${port}`;
cfg.authPort = 3000;
cfg.authHost = '0.0.0.0';

writeFileSync(path, JSON.stringify(cfg, null, 2));
console.log(`patched ${path}: relays=[${relay}] baseUrl=${cfg.baseUrl} authPort=${cfg.authPort}`);
