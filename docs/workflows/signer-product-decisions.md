# Workflow: signer product decisions

Use this when the work is “should we keep wrapping nsecbunkerd / how do people join Bitspark,” not “fix this Docker env and approve the client.”

Linear issue execution (plan → implement → PR) starts **after** this workflow has a written product contract, or when the ticket clearly sits inside an already-agreed contract. Turning notes into frozen files is [freeze product and contract](./freeze-product-contract.md).

## Goal

Enable people to use Bitspark **without assembling third-party signers we do not control**, while remaining **safe** (no long-lived `nsec` in the SPA) and **interoperable** (any NIP-46 signer still works).

Umbrel happy path: install the signer app and Bitspark, open Bitspark, done.

Convenience options (local relay, same-node pairing) must not become the only way to sign.

## When to run this instead of fixing nsecbunkerd

Run this workflow if any of these are true:

- Setup or approval is “unusable” even after the config is technically correct.
- The user has to understand three secrets, two connection URIs, or a hosted admin app we do not run.
- The proposed fix is “document another Prisma/User/baseUrl step” or “repackage nsecbunkerd with nicer UX.”
- The real question is enablement (Umbrel, public Bitspark, our own signer), not a single bug.

Stop nsecbunkerd patching as the main thread. The pain is often **product shape** (hosted multi-tenant bunker used as a one-user local signer), not a missing `.env` line.

## How decisions are made

Separate four layers before choosing code:

| Layer | Question | Example |
| --- | --- | --- |
| Job | Who are we enabling, on what machine? | Umbrel user; public Bitspark visitor with a home signer |
| Protocol | What must Bitspark speak? | NIP-46 (`connect`, `sign_event`, NIP-44). Identity ≠ Lightning (NWC). |
| Deployment | Where do SPA, signer, and relay live? | Same node; public SPA + home signer; later hosted signer we operate |
| Implementation | Which daemon/UI? | Thin NIP-46 signer with our UI; nsecbunkerd only as reference/interop |

Rules:

1. **Protocol over product.** Keep NIP-46. Do not invent a Bitspark-only HTTP signing API. Do not drop support for other NIP-46 signers in Bitspark.
2. **Enablement over wrapping.** We would rather own a small signer that matches the job than ship nsecbunkerd’s admin RPC, `app.nsecbunker.com`, web-auth `User` rows, `create_account`, or LNBits.
3. **Explain the protocol when it is unclear.** If “what is NIP-46” or “are all these stages required” is on the table, answer that before recommending a rewrite or a wrap.
4. **Split nsecbunkerd stages from NIP-46 stages.** Required: hold an encrypted `nsec`, speak NIP-46, approve this client, use a relay both sides can reach. Not required for v1: hosted admin, username@domain bcrypt, OAuth-like `create_account`, NIP-05 provider, policies/tokens, mixing in Lightning.
5. **Stress-test the first convenient model.** Same-box Umbrel is the default onboarding story, not the whole design. Always ask: public Bitspark; signer we run; relay not only localhost; multi-user later.
6. **Defaults are options.** Local relay is a convenient, safer mailbox for same-node use. Users must still be able to use a reachable/public relay. Multi-user is an extension (one identity + client ACL in v1), not a v1 feature and not a dead-end data model.
7. **Custody is explicit.** A signer *we* host (many users) is a **different product**, not v1, and not a design driver. Do not pretend it is the same as “keys stay on the user’s Umbrel.” Other hosted bunkers already exist.
8. **Write the contract before implementing.** Capture line of thought, deployment modes, v1 must/must-not, and a possible approach in `docs/umbrel-app/`. Do not start a nsecbunkerd UX rewrite from chat alone.

## Steps

1. **Name the job.** Who joins, from where (Umbrel node vs public site), what they must not have to bring (Amber, nsec.app, pasted bunker archaeology).
2. **Name the protocol needs.** What Bitspark already requests (NIP-46 methods/kinds, NWC separate). If the protocol is not shared understanding, explain it in plain language first.
3. **List deployment modes** that must not break the protocol:
   - Same-node Bitspark + signer (primary Umbrel onboarding).
   - Public Bitspark + user-run signer (same protocol; mailbox must be reachable).
   - Hosted keys we operate: **out** unless a later explicit product decision.
   - Always: other NIP-46 signers as fallback, not the enablement path.
4. **Map stages to keep vs drop.** Protocol stages stay. nsecbunkerd product stages stay only if they serve a named mode. “It already exists” is not enough.
5. **Choose wrap vs new implementation.** Default: new small NIP-46 signer + own approval UI; nsecbunkerd as reference and strict interop target. Repackage nsecbunkerd only if the goal is compatibility with *its* admin workflows — that is not the enablement goal.
6. **Write `docs/umbrel-app/`** as two frozen files plus strategy: [PRODUCT.md](../umbrel-app/PRODUCT.md) (what it is), [CONTRACT.md](../umbrel-app/CONTRACT.md) (must / must-not). See [freeze product and contract](./freeze-product-contract.md). Do not fold both into the line-of-thought doc.
7. **Only then** cut Linear tickets / implement inside that contract.

## Quality bar

- A newcomer can tell NIP-46 from nsecbunkerd after reading the write-up.
- v1 can be “two Umbrel apps, done” without requiring a public relay, and Mode B is not impossible without a rewrite.
- No recommendation that puts a long-lived `nsec` in the Bitspark SPA as the default.
- No recommendation that makes Lightning the signer’s job.
- Local relay and multi-user are described as default/extension, not as lock-in or as v1 scope creep.

## Stop

- Do not implement nsecbunkerd setup/ACL/docs patches as the “proper solution” to enablement.
- Do not freeze “same box, local relay only” as the architecture.
- Do not wait for Linear triage to answer “is this the right product?” — that question owns this workflow; tickets own execution afterward.

## Related

- Freeze notes into files: [Freeze product and contract](./freeze-product-contract.md)
- Product: [PRODUCT.md](../umbrel-app/PRODUCT.md)
- Contract: [CONTRACT.md](../umbrel-app/CONTRACT.md)
- Line of thought: [Umbrel signer strategy](../umbrel-app/SIGNER-STRATEGY.md)
- Architecture: [ARCHITECTURE.md](../umbrel-app/ARCHITECTURE.md)
