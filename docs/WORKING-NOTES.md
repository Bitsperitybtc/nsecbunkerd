# Development working notes

Session notes, pitfalls, and rationales — intended to improve how we work on this repo over time.
Not a user-facing setup guide; see [SETUP-GUIDE.md](../SETUP-GUIDE.md) for that.

---

## Session: 2026-06-28 (new machine, profile DX, first Bitspark connect)

### Context

- Moved to a new PC; repo on branch `fix/nip46-docker-signing-and-connection-uris`.
- Linear workspace (Bitspark) has an **nsecBunkerd** team with infrastructure issues **NSEC-1…5** and user-story slices **NSEC-6+**.
- An **old** bunker stack was already running (`nsecbunkerd-nsecbunkerd-1` on port **3000**), separate from the new profile-based setup.
- Goal: isolated disposable stacks for testing/Bitspark without touching the old setup.

### Linear plan alignment (at time of session)

| Issue | Title | Status after session |
|-------|--------|----------------------|
| NSEC-1 | Docker relay in local stack | Done (before session) |
| NSEC-2 | One-command bring-up + teardown | **Marked Done** in Linear; code landed on branch |
| NSEC-3 | Headless auth-seeding | **Next** planned task |
| NSEC-4 | Replace Bitspark `nsecbunkerd-local` | Backlog |
| NSEC-5 | From-scratch test runner | Backlog |
| NSEC-6+ | Bitspark user-story slices (S1 profile, etc.) | Backlog; manual Bitspark connect is informal S1 prep |

**Decision:** Finish NSEC-2 properly (including arbitrary named profiles) before starting NSEC-3, because headless auth and the test runner both assume a smooth create/destroy profile flow.

---

## What was implemented (planned)

### Profile lifecycle commands (NSEC-2 extension)

New Make targets and `scripts/profile.sh`:

```shell
make profile-create NAME=<name>   # scaffold profiles/<name>.env
make profile-setup NAME=<name>    # create + keygen + full setup
make profile-destroy NAME=<name> YES=1   # stop + remove config, signer file, profile file
```

**Rationale:**

- `local` is a committed profile, not a good fit for “new PC / throwaway test stack.”
- Copying `profiles/local.env` by hand was error-prone (ports, paths, signer file).
- Disposable profiles match the Linear guiding principle: **provision from zero, tear down cleanly**.

**Design choices:**

- Auto-pick `HOST_PORT` and `RELAY_HOST_PORT` by scanning existing `profiles/*.env` (+10 / +1).
- Reserved names: `default`, `local`.
- `profile-setup` runs `make build` so the local image includes recent code fixes.
- Profile file uses **literal** `DEV_HOST` IP in `CLIENT_RELAY` / `PUBLIC_BASE_URL` (not `$(DEV_HOST)` in those fields) to avoid Make env leakage.

### Env isolation (`.env` footgun)

- `docker-compose.yml` now passes `NSECBUNKER_KEY_NAME` and `ADMIN_NPUBS` via Compose `environment` (from active profile via Make exports), so they override repo `.env` when using profiles.
- `setup.sh` no longer rewrites `.env` for every setup; it exports profile-scoped values instead.
- `profile.sh` unsets parent Make exports before sub-`make setup` so a disposable profile does not inherit `default` profile paths.

**Rationale:** One shared `.env` cannot represent multiple concurrent profiles with different key names / admin npubs.

### Connection URI fix (`clientRelays`)

**Problem:** `connection.txt` contained `relay=ws://relay:8080` (Docker-internal). Browsers/Bitspark need `ws://<host-ip>:<relay-port>`.

**Fixes:**

1. `scripts/write-connection-uris.mjs` — rewrites `connection.txt` and `admin-connection.txt` from `nsecbunker.json` `clientRelays`.
2. `setup.sh` and `make connection` run that script after startup.
3. `src/daemon/run.ts` reloads config from disk before writing URIs (so patched `clientRelays` are seen).

**Rationale:** Published GHCR image may lag branch; post-write script works regardless. Local `make build` in `profile-setup` reduces drift.

### Docs

- [SETUP-GUIDE.md](../SETUP-GUIDE.md) — disposable profiles as primary path for new PCs/testing.
- [README.md](../README.md) — pointer to `profile-setup`.

### Linear

- [NSEC-2](https://linear.app/bitspark/issue/NSEC-2) marked **Done** with updated checklist and comment describing shipped commands.

---

## What was implemented (reactive / pitfalls along the way)

### Bind-mount files owned by `root`

**Symptom:** `~/.nsecbunker-config-<profile>/` files owned by `root`, hard to inspect/edit on host.

**Cause:** Containers run as root; bind-mounted writes become root-owned.

**Mitigation (current, arguably over-engineered):**

- `DOCKER_UID` / `DOCKER_GID` exported from Makefile (`id -u` / `id -g`).
- Entrypoints (`docker-entrypoint.sh`, `migrate-entrypoint.sh`) chown `/app/config` then drop privileges via `setpriv`.
- `setup.sh` `fix_config_permissions()` — one-off root container to chown before/after setup.
- `docker compose run --user` for `add` / `patch-config`.

**Open simplification:** Compose `user: "${DOCKER_UID}:${DOCKER_GID}"` + setup-time chown only would be simpler; entrypoint chown was added to fix **existing** root-owned dirs without `sudo` on the host.

### `make connection` prints too many lines

**Symptom:** Three bunker URIs + status lines; unclear which is for Bitspark.

**Cause:**

1. `write-connection-uris.mjs` logs the client URI.
2. `cat connection.txt` (signing — **use this for Bitspark**).
3. `cat admin-connection.txt` (admin / app.nsecbunker.com — **not** Bitspark login).

**Improvement idea:** Label outputs in Makefile or only print `connection.txt` by default.

### Web auth password unknown after `profile-setup`

**Symptom:** Bitspark/bunker approval page asks for a password; user does not know it.

**Cause:** `profile-setup` auto-generates `WEB_AUTH_PASSWORD` with `openssl rand` and never prints it.

**Workaround:** `make web-auth-password PROFILE=<name>` (set a known password).

**Improvement idea:** Print web auth password at end of `profile-setup`, or prompt like interactive `make setup`, or write to a gitignored file with a clear name.

### Port / env leakage from parent Make

**Symptoms:**

- `profile-create` picked `HOST_PORT=3009` (default profile’s port) instead of next free port.
- `CLIENT_RELAY` / `PUBLIC_BASE_URL` had empty host (`ws://:7778`) when `DEV_HOST` was exported empty from parent Make.

**Fix:** Only pass `HOST_PORT` / `DEV_HOST` from CLI when `origin` is `command line`; use literal IP in generated profile files for client URLs.

### Sub-make inherits default profile exports

**Symptom:** `profile-setup` wrote `signer-identity.txt` instead of `signer-identity-<name>.txt`.

**Fix:** `env -u SIGNER_IDENTITY_FILE … make setup PROFILE="$NAME"` (and other isolating vars).

---

## Pitfall collection (quick reference)

| Pitfall | Symptom | What to use / do |
|--------|---------|------------------|
| Docker-internal relay in URI | Bitspark cannot connect; `relay=ws://relay:8080` | `make connection` (refreshes URIs) or use `CLIENT_RELAY` from profile; paste **connection.txt** only |
| Wrong bunker URI | Admin vs signing pubkey | **Bitspark:** `connection.txt` (signing pubkey). **Admin UI:** `admin-connection.txt` |
| Unknown approval password | Browser asks for password after bunker connect | **Web auth password** — `make web-auth-password PROFILE=<name>`. Not `signer-identity*.txt` passphrase |
| Encryption passphrase vs web auth | Confusion between two secrets | `signer-identity-*.txt` = unlock key at container start. Web auth = browser approval page only |
| Root-owned config dir | `ls` shows `root root` | Re-run stack after permission fixes; or `sudo chown -R $USER ~/.nsecbunker-config-*` once |
| Old stack vs new profiles | Multiple bunkers on different ports | Old: port 3000, project `nsecbunkerd`. Profiles: e.g. test4 on 3039/7779 — isolated by `PROJECT` + `CONFIG_DIR` |
| Lost signing `nsec` | Cannot recover signing identity | Printed once at `profile-setup` / `keygen` — not stored in repo; backup in password manager |
| `profile-setup` silent web password | Cannot approve in browser | Always run `web-auth-password` after setup until we print/persist it |
| Migrations service name | “Do I need to migrate?” | **Automatic** Prisma DB schema apply on `docker compose up` — not “migrate from old PC” |
| `migrate-entrypoint.sh` name | Sounds like data migration | Only runs `prisma migrate deploy` on SQLite + optional chown wrapper |
| Concurrent profiles | Port clashes | Each profile gets unique `HOST_PORT`, `RELAY_HOST_PORT`, `PROJECT`; auto-picked on create |
| Linear not connected on new PC | MCP tools unavailable | Authenticate Linear MCP once per machine |

---

## Architecture reminders (three identities)

Documented fully in [SETUP-CONCEPTS.md](../SETUP-CONCEPTS.md). Short form:

1. **Signing identity** — the npub/nsec you sign as (`keygen` / imported key).
2. **Bunker communication identity** — NIP-46 remote signer; hex in `connection.txt` / `admin-connection.txt` (different files, different pubkeys in this codebase).
3. **Admin identity** — your `ADMIN_NPUBS`; who may manage the bunker.

For **Bitspark login**, paste **`connection.txt`** URI and use **web auth password** on the approval page (`PUBLIC_BASE_URL`, e.g. `http://<lan-ip>:3039/requests/...`).

---

## Suggested workflow improvements (for us)

1. **After every `profile-setup`:** run `make web-auth-password PROFILE=<name>` with a chosen password (until setup prints or saves it).
2. **Before Bitspark test:** `make connection PROFILE=<name>` and use **only the first** of the two final `bunker://` lines (or `cat connection.txt` via compose).
3. **Close Linear issues when shipping** — NSEC-2 was implemented but still Backlog until end of session.
4. **Prefer `make profile-destroy NAME=… YES=1`** over manual `docker kill` — scoped to one profile.
5. **Simplify UID handling** when convenient: compose `user:` + setup chown only; drop entrypoint `setpriv` if no legacy root-owned dirs remain.
6. **Label `make connection` output** — reduce confusion between signing and admin URIs.
7. **Next planned work:** [NSEC-3](https://linear.app/bitspark/issue/NSEC-3) headless ACL seeding (no browser approval for tests).

---

## Close-out issues from commit / Linear sync

### Disposable profile files are local artifacts

`profiles/test3.env`, `profiles/test4.env`, and `profiles/test5.env` were generated while validating disposable stacks. They should **not** be committed:

- They contain machine-specific LAN IPs and ports.
- They represent throwaway signer/config identities.
- The canonical committed profiles remain `profiles/default.env` and `profiles/local.env`.

Action taken: `.gitignore` now excludes `profiles/test*.env` and `profiles/*-test.env`.

### Linear-first workflow should be explicit

We created `.cursor/rules/linear-first.mdc` so future sessions remember to involve Linear when discussion turns into actionable work.

Working rule:

- Check Linear before coding if the topic is actionable.
- Create an issue or add a comment when there is no suitable tracker yet.
- Keep issue status/comments aligned with planned, started, blocked, validated, shipped, or deferred work.
- Tie commits and branch work back to Linear IDs where practical.

Linear tracking created:

- [NSEC-12](https://linear.app/bitspark/issue/NSEC-12/a6-polish-disposable-profile-ux-and-connection-output) — profile UX and connection output polish.
- [NSEC-13](https://linear.app/bitspark/issue/NSEC-13/process-keep-nsecbunkerd-work-tied-to-linear) — Linear-first process rule; completed after committing the Cursor rule.
- [NSEC-14](https://linear.app/bitspark/issue/NSEC-14/a7-simplify-docker-uid-and-config-ownership-handling) — simplify Docker UID/config ownership handling.

### Validation friction

`npm run build` initially failed because `node_modules` did not contain local dev binaries (`tsup: not found`). After `npm ci`, the build passed.

Notes:

- This was an environment/dependency-install issue, not a TypeScript compile failure.
- `npm ci` reported existing audit warnings (18 locally; GitHub also reported default-branch vulnerabilities on push). We did not change dependencies in this session.
- For future from-scratch validation, run `npm ci` before build unless dependencies are already installed.

### Commit and push split

Two commits were pushed to `fix/nip46-docker-signing-and-connection-uris`:

- `bd767e0` — `feat(NSEC-2): streamline disposable profile setup`
- `4f183ca` — `chore(NSEC-13): add Linear-first workflow rule`

This split was useful because the first commit is product/DX behavior, while the second is process guidance.

### Possible future doc split

This file is still fine as a single session note, but if it grows, split by purpose:

- `docs/PITFALLS.md` — recurring operational gotchas and fixes.
- `docs/PROCESS.md` — Linear-first workflow, branching, commit hygiene.
- `docs/SESSION-NOTES.md` — chronological notes and rationale from each working session.

Keep `SETUP-GUIDE.md` as the user-facing “how to run it” doc, and keep `WORKING-NOTES.md` or its successors for “what we learned and why.”

---

## Files touched this session (branch work)

| Area | Files |
|------|--------|
| Profile lifecycle | `scripts/profile.sh`, `Makefile` |
| Connection URIs | `scripts/write-connection-uris.mjs`, `src/daemon/run.ts`, `setup.sh` |
| Permissions | `scripts/docker-entrypoint.sh`, `scripts/migrate-entrypoint.sh`, `docker-compose.yml`, `setup.sh` |
| Docs | `SETUP-GUIDE.md`, `README.md`, this file |

Generated locally (do not commit): `profiles/test3.env`, `profiles/test4.env`, `profiles/test5.env`, `signer-identity-test*.txt`, `~/.nsecbunker-config-test*`.

---

## Related links

- [SETUP-GUIDE.md](../SETUP-GUIDE.md) — how to run profiles
- [SETUP-CONCEPTS.md](../SETUP-CONCEPTS.md) — identities, relays, secrets
- Linear project: [nsecbunkerd: easy local signer (DX)](https://linear.app/bitspark/project/nsecbunkerd-easy-local-signer-dx-9c3e2a164d18)
