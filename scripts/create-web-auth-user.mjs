// Create/update the local web-auth user that protects the browser approval page
// at /requests/<request-id>.
//
// Runs inside the container. Derives:
//   - username / domain  from NSECBUNKER_KEY_NAME (name@domain)
//   - pubkey             from /app/config/connection.txt (the signing identity pubkey)
//
// Requires env WEB_AUTH_PASSWORD.
import bcrypt from 'bcrypt';
import { readFileSync } from 'node:fs';
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

const keyName = process.env.NSECBUNKER_KEY_NAME;
if (!keyName || !keyName.includes('@')) {
  throw new Error('NSECBUNKER_KEY_NAME must be set in the form name@domain');
}
const [username, domain] = keyName.split('@');

const password = process.env.WEB_AUTH_PASSWORD;
if (!password) throw new Error('WEB_AUTH_PASSWORD is missing');

const conn = readFileSync('/app/config/connection.txt', 'utf8').trim();
const pubkey = conn.replace(/^bunker:\/\//, '').replace(/\?.*$/, '');
if (!/^[0-9a-f]{64}$/.test(pubkey)) {
  throw new Error('Could not parse signing pubkey from connection.txt: ' + conn);
}

const hashed = await bcrypt.hash(password, 10);

await prisma.user.upsert({
  where: { username },
  update: { domain, password: hashed, pubkey, email: '' },
  create: { username, domain, password: hashed, pubkey, email: '' },
});

console.log(`Created/updated web auth user ${username}@${domain} for pubkey ${pubkey}`);
await prisma.$disconnect();
