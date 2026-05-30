#!/usr/bin/env node
// Smoke-test the local Nostr relay: publish a kind-1 event and read it back.
//
// Env:
//   RELAY_URL  (default ws://localhost:7777)
import WebSocket from 'ws';
import { Relay } from 'nostr-tools/relay';
import { finalizeEvent, generateSecretKey } from 'nostr-tools/pure';

globalThis.WebSocket = WebSocket;

const relayUrl = process.env.RELAY_URL || 'ws://localhost:7777';
const timeoutMs = Number(process.env.RELAY_SMOKE_TIMEOUT_MS || 15000);

const sk = generateSecretKey();
const content = `relay-smoke-${Date.now()}`;
const event = finalizeEvent(
  {
    kind: 1,
    created_at: Math.floor(Date.now() / 1000),
    tags: [],
    content,
  },
  sk,
);

let relay;
const timer = setTimeout(() => {
  console.error(`relay-smoke: timed out after ${timeoutMs}ms (relay=${relayUrl})`);
  relay?.close();
  process.exit(1);
}, timeoutMs);

try {
  relay = await Relay.connect(relayUrl);
} catch (err) {
  clearTimeout(timer);
  console.error(`relay-smoke: failed to connect to ${relayUrl}:`, err.message || err);
  process.exit(1);
}

relay.subscribe(
  [{ kinds: [1], authors: [event.pubkey], since: event.created_at - 1 }],
  {
    onevent(e) {
      if (e.id !== event.id) return;
      clearTimeout(timer);
      console.log(`relay-smoke: ok (relay=${relayUrl} id=${e.id})`);
      relay.close();
      process.exit(0);
    },
  },
);

try {
  await relay.publish(event);
} catch (err) {
  clearTimeout(timer);
  console.error('relay-smoke: publish failed:', err.message || err);
  relay.close();
  process.exit(1);
}
