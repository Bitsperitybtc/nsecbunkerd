# Workflow: freeze product and contract

Use this when [SIGNER-STRATEGY.md](../umbrel-app/SIGNER-STRATEGY.md) (or similar working notes) exists, and the question is “what’s next — requirements, dos/don’ts?” — not “is NIP-46 the right protocol?” and not “open a Linear ticket.”

Run [signer product decisions](./signer-product-decisions.md) first if wrap-vs-new or protocol-vs-product is still open. This workflow starts **after** that. Frozen outputs: [PRODUCT.md](../umbrel-app/PRODUCT.md), [CONTRACT.md](../umbrel-app/CONTRACT.md).

## Goal

Turn line-of-thought notes into two short frozen files without rewriting the essay, without reopening agreed protocol, and without treating convenience (local relay, Umbrel config, Approve popup) as a second auth mechanism.

## When to run this

- Strategy says “working notes, not a spec.”
- Someone asks whether to write must / must-not / avoid-at-all-costs.
- Open questions are labeled (Mode A/B/C, envelope key, well-known URL) and the reader cannot decide because the labels were never explained.
- The conversation keeps contrasting a **rejected** alternative (e.g. HTTP signing) after NIP-46 is already agreed.

Do **not** wait for Linear. Product freeze owns this; tickets own execution after [CONTRACT.md](../umbrel-app/CONTRACT.md) exists.

## How decisions are made

| Layer | Do | Do not |
| --- | --- | --- |
| Product | Short “what it is / happy path / what it is not.” Own file. | Mix must-lists into the product page. |
| Contract | Job, protocol, must, must-not, v1 defaults, repo split. Own file. | A second strategy essay. |
| Protocol | One NIP-46 path everywhere. Local vs public = **which relay URL** (and whether the SPA already knows it). | A Bitspark-only HTTP `POST /sign`. A special “local auth” stack. |
| Pairing | Mailbox + `connect` + Approve this client. Signing events is a later step. | Call pairing “login with password.” Equate it with how events are signed. |
| Convenience | Local relay as default mailbox; inject **browser-facing** URL into the static SPA; optional open of signer UI when we know that URL. | Treat local relay as lock-in. Treat QR as the Umbrel happy path (node has no camera). |
| Scope | New signer repo; nsecbunkerd = reference/interop. Hosted keys (custodial bunker we run) **out** unless a later explicit product decision. | Implement inside nsecbunkerd and “migrate later.” Keep Mode C as a v1 design driver. |

## Steps

1. **Do not start from a blank requirements dump.** Promote existing notes. Keep strategy as line of thought.
2. **Explain before asking to decide.** If the hang is “authentication,” explain pairing (shared relay, throwaway client key, Approve) vs signing. Do not ask people to pick Mode B / envelope key / well-known URL until those sentences exist in plain language.
3. **Prefer config over a new product fork.** A reachable mailbox for public Bitspark is a relay setting, not a decision to operate a public relay now.
4. **Same path as other signers.** Bitspark’s “Bitspark Signer” choice may auto-fill mailbox (and optional signer UI URL). It still uses NIP-46 (`nostrconnect` / `connect`). Other sign-in options stay for Amber / bunker URI / NIP-07.
5. **Stop talking about rejected alternatives** once the protocol is agreed. HTTP signing is a must-not one-liner, not a live design thread.
6. **Write two files** under `docs/umbrel-app/`:
   - `PRODUCT.md` — what it is (few paragraphs).
   - `CONTRACT.md` — constraints an implementer cannot violate.
7. **Park indefinitely** anything that is a different trust story (we hold keys) or a different device class (QR for a camera signer). Revisit only as a new product decision.
8. **Only then** create the new git root / Linear tickets inside the contract.

## Quality bar

- A reader who already knows how event signing works can still understand pairing after the write-up.
- Local Umbrel and public Bitspark are described as the **same** NIP-46 path.
- Product and contract are separate files; strategy is not the spec.
- Agreed protocol is not re-litigated in the next reply.

## Stop

- Do not keep HTTP-vs-NIP-46 alive after NIP-46 is agreed.
- Do not invent a local-only signing API because “this sign-in option could set localhost.” Localhost is the **mailbox URL**, not a REST signer.
- Do not use Mode A/B/C, “envelope key,” or “well-known” as decision prompts without defining them in the same message.
- Do not implement in `nsecbunkerd` on the theory that extraction is later.
- Do not divert a freeze conversation into Linear triage unless the user asks.

## Related

- Decide wrap vs new: [Signer product decisions](./signer-product-decisions.md)
- Product: [PRODUCT.md](../umbrel-app/PRODUCT.md)
- Contract: [CONTRACT.md](../umbrel-app/CONTRACT.md)
- Line of thought: [SIGNER-STRATEGY.md](../umbrel-app/SIGNER-STRATEGY.md)
- Architecture (after freeze): [ARCHITECTURE.md](../umbrel-app/ARCHITECTURE.md)
