// Generic signing-identity generator.
//
// Uses Node's built-in crypto (secp256k1) for entropy and key derivation, and a
// self-contained bech32 (BIP-173) encoder for the nsec/npub formatting. It does
// NOT depend on nostr-tools. The key itself is a standard secp256k1/Schnorr key;
// nsec/npub are just bech32 encodings of the raw bytes.
//
// Output (stdout):
//   nsec=...
//   npub=...
//   pubkey_hex=...

import { generateKeyPairSync } from 'node:crypto';

const CHARSET = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const GEN = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];

function polymod(values) {
  let chk = 1;
  for (const v of values) {
    const top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (let i = 0; i < 5; i++) if ((top >> i) & 1) chk ^= GEN[i];
  }
  return chk;
}

function hrpExpand(hrp) {
  const out = [];
  for (let i = 0; i < hrp.length; i++) out.push(hrp.charCodeAt(i) >> 5);
  out.push(0);
  for (let i = 0; i < hrp.length; i++) out.push(hrp.charCodeAt(i) & 31);
  return out;
}

function createChecksum(hrp, data) {
  const values = hrpExpand(hrp).concat(data, [0, 0, 0, 0, 0, 0]);
  const mod = polymod(values) ^ 1;
  const out = [];
  for (let i = 0; i < 6; i++) out.push((mod >> (5 * (5 - i))) & 31);
  return out;
}

function convertBits(data, from, to, pad) {
  let acc = 0;
  let bits = 0;
  const out = [];
  const maxv = (1 << to) - 1;
  for (const value of data) {
    acc = (acc << from) | value;
    bits += from;
    while (bits >= to) {
      bits -= to;
      out.push((acc >> bits) & maxv);
    }
  }
  if (pad && bits > 0) out.push((acc << (to - bits)) & maxv);
  return out;
}

function bech32Encode(hrp, bytes) {
  const data = convertBits([...bytes], 8, 5, true);
  const combined = data.concat(createChecksum(hrp, data));
  let out = hrp + '1';
  for (const d of combined) out += CHARSET[d];
  return out;
}

function left32(buf) {
  if (buf.length === 32) return buf;
  if (buf.length > 32) return buf.subarray(buf.length - 32);
  const padded = Buffer.alloc(32);
  buf.copy(padded, 32 - buf.length);
  return padded;
}

const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'secp256k1' });
const jwk = privateKey.export({ format: 'jwk' });

const d = left32(Buffer.from(jwk.d, 'base64url')); // 32-byte private scalar
const x = left32(Buffer.from(jwk.x, 'base64url')); // 32-byte x-only pubkey (BIP-340)

console.log('nsec=' + bech32Encode('nsec', d));
console.log('npub=' + bech32Encode('npub', x));
console.log('pubkey_hex=' + x.toString('hex'));
