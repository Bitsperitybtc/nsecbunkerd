// Rewrite connection.txt and admin-connection.txt using client-facing relays from
// nsecbunker.json. Safe to run after setup or restart when the image wrote Docker-internal relays.
//
// Env:
//   CONFIG_PATH  path to nsecbunker.json (default /app/config/nsecbunker.json)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { getPublicKey } from 'nostr-tools';

const configPath = process.env.CONFIG_PATH || '/app/config/nsecbunker.json';
const configDir = path.dirname(configPath);
const cfg = JSON.parse(readFileSync(configPath, 'utf8'));

function normalizeRelay(r) {
  const trimmed = r.trim();
  if (trimmed.startsWith('wss://') || trimmed.startsWith('ws://')) return trimmed;
  return `wss://${trimmed.replace(/^\/+/, '')}`;
}

function buildBunkerUri(pubHex, relays) {
  const params = new URLSearchParams();
  for (const r of relays) {
    params.append('relay', normalizeRelay(r));
  }
  return `bunker://${pubHex}?${params.toString()}`;
}

function hexToBytes(hex) {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function readPubkeyFromConnectionFile(filePath) {
  if (!existsSync(filePath)) return null;
  const existing = readFileSync(filePath, 'utf8').trim();
  const match = existing.match(/^bunker:\/\/([0-9a-f]+)\?/i);
  return match ? match[1] : null;
}

const clientRelays =
  cfg.nostr?.clientRelays?.length > 0 ? cfg.nostr.clientRelays : cfg.nostr?.relays ?? [];
const adminRelays =
  cfg.admin?.clientRelays?.length > 0 ? cfg.admin.clientRelays : cfg.admin?.adminRelays ?? [];

if (adminRelays.length > 0 && cfg.admin?.key) {
  const pubHex = getPublicKey(hexToBytes(cfg.admin.key));
  const adminUri = buildBunkerUri(pubHex, adminRelays);
  writeFileSync(path.join(configDir, 'admin-connection.txt'), adminUri);
  console.log(`updated admin-connection.txt relays -> ${adminRelays.join(', ')}`);
}

const connectionPath = path.join(configDir, 'connection.txt');
const clientPubHex = readPubkeyFromConnectionFile(connectionPath);
if (!clientPubHex) {
  console.warn('connection.txt missing or unreadable; skip client URI refresh');
} else if (clientRelays.length > 0) {
  const clientUri = buildBunkerUri(clientPubHex, clientRelays);
  writeFileSync(connectionPath, clientUri);
  console.log(`updated connection.txt relays -> ${clientRelays.join(', ')}`);
  console.log(clientUri);
}
