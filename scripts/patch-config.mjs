// Patch relay + web-auth settings into an existing nsecbunker.json without
// disturbing generated values (e.g. admin.key). Runs inside the container.
//
// Env:
//   NSECBUNKER_RELAY            bunker/admin NDK relays (default wss://nos.lol)
//   NSECBUNKER_CLIENT_RELAY     optional client-facing relay for connection.txt
//   NSECBUNKER_PUBLIC_BASE_URL  optional browser approval base URL
//   NSECBUNKER_HOST_PORT        fallback for baseUrl when PUBLIC_BASE_URL unset (default 3009)
import { readFileSync, writeFileSync } from 'node:fs';

const path = '/app/config/nsecbunker.json';
const relay = process.env.NSECBUNKER_RELAY || 'wss://nos.lol';
const clientRelay = (process.env.NSECBUNKER_CLIENT_RELAY || '').trim();
const publicBaseUrl = (process.env.NSECBUNKER_PUBLIC_BASE_URL || '').trim();
const port = process.env.NSECBUNKER_HOST_PORT || '3009';

const cfg = JSON.parse(readFileSync(path, 'utf8'));

cfg.nostr = cfg.nostr || {};
cfg.nostr.relays = [relay];
if (clientRelay) {
  cfg.nostr.clientRelays = [clientRelay];
} else {
  delete cfg.nostr.clientRelays;
}

cfg.admin = cfg.admin || {};
cfg.admin.adminRelays = [relay];
if (clientRelay) {
  cfg.admin.clientRelays = [clientRelay];
} else {
  delete cfg.admin.clientRelays;
}

cfg.baseUrl = publicBaseUrl || `http://localhost:${port}`;
cfg.authPort = 3000;
cfg.authHost = '0.0.0.0';

writeFileSync(path, JSON.stringify(cfg, null, 2));
const clientNote = clientRelay ? ` clientRelays=[${clientRelay}]` : '';
console.log(
  `patched ${path}: relays=[${relay}]${clientNote} baseUrl=${cfg.baseUrl} authPort=${cfg.authPort}`
);
