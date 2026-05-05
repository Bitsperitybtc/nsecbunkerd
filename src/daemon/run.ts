import NDK, { NDKPrivateKeySigner, Nip46PermitCallback, Nip46PermitCallbackParams } from '@nostr-dev-kit/ndk';
import fs from 'fs';
import path from 'path';
import { getPublicKey, nip19 } from 'nostr-tools';
import { Backend } from './backend/index.js';
import {
    IMethod,
    checkIfPubkeyAllowed,
} from './lib/acl/index.js';
import AdminInterface from './admin/index.js';
import { IConfig } from '../config/index.js';
import { NDKRpcRequest } from '@nostr-dev-kit/ndk';
import prisma from '../db.js';
import { DaemonConfig } from './index.js';
import { decryptNsec } from '../config/keys.js';
import { requestAuthorization } from './authorize.js';
import Fastify, { type FastifyInstance } from 'fastify';
import FastifyFormBody from "@fastify/formbody";
import FastifyView from '@fastify/view';
import Handlebars from "handlebars";
import {authorizeRequestWebHandler, processRequestWebHandler} from "./web/authorize.js";
import {processRegistrationWebHandler} from "./web/authorize.js";

export type Key = {
    name: string;
    npub?: string;
};

export type KeyUser = {
    name: string;
    pubkey: string;
    description?: string;
    createdAt: Date;
    lastUsedAt?: Date;
};

function getKeys(config: DaemonConfig) {
    return async (): Promise<Key[]> => {
        let lockedKeyNames = Object.keys(config.allKeys);
        const keys: Key[] = [];

        for (const [name, nsec] of Object.entries(config.keys)) {
            const hexpk = nip19.decode(nsec).data as string;
            const user = await new NDKPrivateKeySigner(hexpk).user();
            const key = {
                name,
                npub: user.npub,
                userCount: await prisma.keyUser.count({ where: { keyName: name } }),
                tokenCount: await prisma.token.count({ where: { keyName: name } })
            };

            lockedKeyNames = lockedKeyNames.filter((keyName) => keyName !== name);
            keys.push(key);
        }

        for (const name of lockedKeyNames) {
            keys.push({ name });
        }

        return keys;
    };
}

function getKeyUsers(config: IConfig) {
    return async (req: NDKRpcRequest): Promise<KeyUser[]> => {
        const keyUsers: KeyUser[] = [];
        const keyName = req.params[0];

        const users = await prisma.keyUser.findMany({
            where: {
                keyName,
            },
            include: {
                signingConditions: true,
            },
        });

        for (const user of users) {
            const keyUser = {
                id: user.id,
                name: user.keyName,
                pubkey: user.userPubkey,
                description: user.description || undefined,
                createdAt: user.createdAt,
                lastUsedAt: user.lastUsedAt || undefined,
                revokedAt: user.revokedAt || undefined,
                signingConditions: user.signingConditions, // Include signing conditions
            };

            keyUsers.push(keyUser);
        }

        return keyUsers;
    };
}

/**
 * Called by the NDKNip46Backend when an action requires authorization
 * @param keyName -- Key attempting to be used
 * @param adminInterface
 * @returns
 */
function signingAuthorizationCallback(keyName: string, adminInterface: AdminInterface): Nip46PermitCallback {
    return async (p: Nip46PermitCallbackParams): Promise<boolean> => {
        const { id, method, pubkey: remotePubkey, params: payload } = p;
        console.log(`🔑 ${keyName} is being requested to ${method} by ${nip19.npubEncode(remotePubkey)}, request ${id}`);

        if (!adminInterface.requestPermission) {
            throw new Error('adminInterface.requestPermission is not defined');
        }

        try {
            const keyAllowed = await checkIfPubkeyAllowed(keyName, remotePubkey, method as IMethod, payload);

            if (keyAllowed === true || keyAllowed === false) {
                console.log(`🔎 ${nip19.npubEncode(remotePubkey)} is ${keyAllowed ? 'allowed' : 'denied'} to ${method} with key ${keyName}`);
                return keyAllowed;
            }

            return new Promise((resolve) => {
                requestAuthorization(
                    adminInterface,
                    keyName,
                    remotePubkey,
                    id,
                    method,
                    payload
                )
                    .then(() => resolve(true))
                    .catch(() => resolve(false));
            });
        } catch(e) {
            console.log('callbackForKey error:', e);
        }

        return false;
    };
}

export default async function run(config: DaemonConfig) {
    const daemon = new Daemon(config);
    await daemon.start();
}

class Daemon {
    private config: DaemonConfig;
    private activeKeys: Record<string, any>;
    private adminInterface: AdminInterface;
    private ndk: NDK;
    public fastify: FastifyInstance;

    constructor(config: DaemonConfig) {
        this.config = config;
        this.activeKeys = config.keys;
        this.adminInterface = new AdminInterface(config.admin, config.configFile);

        this.adminInterface.getKeys = getKeys(config);
        this.adminInterface.getKeyUsers = getKeyUsers(config);
        this.adminInterface.unlockKey = this.unlockKey.bind(this);
        this.adminInterface.loadNsec = this.loadNsec.bind(this);

        this.fastify = Fastify({ logger: true });
        this.fastify.register(FastifyFormBody);

        this.ndk = new NDK({
            explicitRelayUrls: config.nostr.relays,
        });
        this.ndk.pool.on('relay:connect', (r) => console.log(`✅ Connected to ${r.url}`) );
        this.ndk.pool.on('relay:notice', (n, r) => { console.log(`👀 Notice from ${r.url}`, n); });

        this.ndk.pool.on('relay:disconnect', (r) => {
            console.log(`🚫 Disconnected from ${r.url}`);
        });
    }

    async startWebAuth() {
        if (!this.config.authPort) return;

        const urlPrefix = new URL(this.config.baseUrl as string).pathname.replace(/\/+$/, '');

        this.fastify.register(FastifyView, {
            engine: {
                handlebars: Handlebars,
            },
            defaultContext: {
                urlPrefix 
            }
        });

        this.fastify.listen({ port: this.config.authPort, host: this.config.authHost });

        this.fastify.get('/requests/:id', authorizeRequestWebHandler);
        this.fastify.post('/requests/:id', processRequestWebHandler);
        this.fastify.post('/register/:id', processRegistrationWebHandler);
    }

    async startKeys() {
        console.log('🔑 Starting keys', Object.keys(this.config.keys));
        for (const [name, nsec] of Object.entries(this.config.keys)) {
            console.log(`🔑 Starting ${name}...`);
            await this.startKey(name, nsec);
        }

        // Load unencrypted keys
        const config = await this.adminInterface.config();
        for (const [keyName, settings ] of Object.entries(config.keys))  {
            if (!settings.key) {
                continue;
            }

            const nsec = nip19.nsecEncode(settings.key);
            this.loadNsec(keyName, nsec);
        }
    }

    async start() {
        await this.ndk.connect(5000);
        await this.startWebAuth();
        await this.startKeys();
        this.writeClientNip46ConnectionUri();

        console.log('✅ nsecBunker ready to serve requests.');
    }

    /**
     * NIP-46 clients (Bitspark, etc.) must use the *signing* key pubkey and `nostr.relays`,
     * not the admin signer — see admin-connection.txt for app.nsecbunker.com.
     */
    private writeClientNip46ConnectionUri() {
        const unlocked = this.activeKeys as Record<string, string>;
        const names = Object.keys(unlocked).sort();
        if (names.length === 0) {
            return;
        }

        const relays = this.config.nostr?.relays ?? [];
        if (relays.length === 0) {
            console.warn('⚠️ No config.nostr.relays; skipping NIP-46 client connection.txt');
            return;
        }

        const keyName = names[0]!;
        if (names.length > 1) {
            console.warn(
                `⚠️ Multiple unlocked keys; connection.txt uses "${keyName}". Others: ${names.slice(1).join(', ')}`
            );
        }

        const raw = unlocked[keyName]!.trim();
        let skHex: string;
        if (raw.startsWith('nsec1')) {
            const decoded = nip19.decode(raw);
            if (decoded.type !== 'nsec' || typeof decoded.data !== 'string') {
                console.warn(`⚠️ Could not decode nsec for "${keyName}"; skipping connection.txt`);
                return;
            }
            skHex = decoded.data;
        } else {
            skHex = raw;
        }

        let pubHex: string;
        try {
            pubHex = getPublicKey(skHex);
        } catch (e) {
            console.warn(`⚠️ Could not derive pubkey for "${keyName}"; skipping connection.txt`, e);
            return;
        }

        const params = new URLSearchParams();
        for (const r of relays) {
            const trimmed = r.trim();
            const wss =
                trimmed.startsWith('wss://') || trimmed.startsWith('ws://')
                    ? trimmed
                    : `wss://${trimmed.replace(/^\/+/, '')}`;
            params.append('relay', wss);
        }

        const uri = `bunker://${pubHex}?${params.toString()}`;
        const dir = path.dirname(this.config.configFile);
        fs.writeFileSync(path.join(dir, 'connection.txt'), uri);

        console.log(`\n\nNIP-46 client connection (paste into Bitspark / NIP-46 clients):\n\n${uri}\n\n`);
    }

    /**
     * Method to start a key's backend
     * @param name Name of the key
     * @param nsec NSec of the key
     */
    async startKey(name: string, nsec: string) {
        const cb = signingAuthorizationCallback(name, this.adminInterface);
        const trimmed = nsec.trim();
        let hexpk: string;

        if (trimmed.startsWith('nsec1')) {
            try {
                const decoded = nip19.decode(trimmed);
                if (decoded.type !== 'nsec') {
                    throw new Error(`Expected nsec bech32, got ${decoded.type}`);
                }
                hexpk = decoded.data as string;
            } catch (e) {
                console.error(`Error loading key ${name}:`, e);
                return;
            }
        } else {
            hexpk = trimmed;
        }
        
        const backend = new Backend(this.ndk, this.fastify, hexpk, cb, this.config.baseUrl);
        await backend.start();
    }

    async unlockKey(keyName: string, passphrase: string): Promise<boolean> {
        const keyData = this.config.allKeys[keyName];
        const { iv, data } = keyData;

        const nsec = decryptNsec(iv, data, passphrase);
        this.activeKeys[keyName] = nsec;

        this.startKey(keyName, nsec);

        return true;
    }

    loadNsec(keyName: string, nsec: string) {
        this.activeKeys[keyName] = nsec;

        this.startKey(keyName, nsec);
    }
}