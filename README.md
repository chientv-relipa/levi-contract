# Levi — AI Agent Firewall on Sui (Move)

Levi is an **on-chain firewall for AI agents** on Sui. When an AI agent wants to broadcast
a transaction, it first submits the **encrypted intent** to Levi. An independent off-chain
relayer (running an LLM) decrypts and analyzes it, then writes a verdict back on-chain. The
agent only broadcasts the real transaction if the verdict is **Approved** — otherwise the
action is **Blocked**, or **Escalated** to the human owner for manual approval.

Levi is a **gatekeeper, not an executor**: it never holds private keys, never signs, and
never moves funds. It only stores intents, enforces policy, and records an immutable,
public reputation for each agent.

## How it works

```
Agent builds tx (unsigned) ──encrypt──▶ submit_action ──▶ Action(Pending) on-chain ─emit─▶ ActionSubmitted
                                                                                              │
                              off-chain relayer: decrypt → LLM analysis → raw_score ◀─────────┘
                                                                                              │
            verdict_action(raw_score) ──▶ Approved / Escalated / Blocked  +  update reputation
                                                                                              │
   Approved ─▶ agent signs & broadcasts the real tx        Escalated ─▶ owner approve / reject
```

- **On-chain** = storage + authority enforcement + deterministic policy (thresholds) +
  immutable verdict/reputation record. No AI, no tx execution.
- **Off-chain relayer** = decrypt + LLM threat analysis → produces `raw_score`. (Separate
  service; not in this package.)

## Layout

One module = one file. Constants and error codes are module-private (each `#[error]` lives
in the module that raises it). Handlers are **one module per instruction**.

```
sui-contract/
├── Move.toml                       # package `contract`, edition 2024, address `levi`
├── sources/
│   ├── common/
│   │   ├── constants.move          # MAX_PAYLOAD, MAX_ALLOWED_TARGETS (public accessors)
│   │   └── events.move             # event schema + emit_* helpers
│   ├── states/                     # data objects + package-internal ops + getters
│   │   ├── capability.move         # AdminCap, RelayerCap, BootstrapCap
│   │   ├── config.move             # Config singleton: policy, getters, create/update
│   │   ├── registry.move           # AgentRegistry: Table<wallet, Agent ID>
│   │   ├── agent.move              # Agent: identity, policy, whitelist, reputation
│   │   └── action.move             # Action: status codes, guards, verdict mutators
│   └── handlers/                   # entry functions — one module per instruction
│       ├── initialize.move
│       ├── update_config.move
│       ├── update_maintenance.move
│       ├── register_agent.move
│       ├── activate_agent.move
│       ├── deactivate_agent.move
│       ├── update_agent_program_target.move
│       ├── submit_action.move
│       ├── verdict_action.move
│       ├── approve_action.move
│       └── reject_action.move
├── tests/                          # Move unit / scenario tests (41 tests)
├── sdk/                            # TypeScript SDK (PTB builders + crypto) — see sdk/README.md
└── tests-ts/                       # crypto unit tests + testnet e2e tests
```

## On-chain objects

| Object | Kind | Holds |
|--------|------|-------|
| `Config` | Shared (singleton) | relayer addr, x25519 encryption key, thresholds, EMA params, maintenance flag |
| `AgentRegistry` | Shared (singleton) | `Table<wallet → Agent ID>` lookup |
| `Agent` | Shared (one per agent) | wallet, owner, spend_limit, allowed_targets[10], **reputation** (threat_score, strikes), counters, `action_index` |
| `Action` | Shared (one per action) | encrypted payload, target, value, commitment, status, decision, raw_score, reasoning_hash |
| `AdminCap` | Owned | admin authority |
| `RelayerCap` | Owned | relayer (verdict) authority |
| `BootstrapCap` | Owned (one-shot) | consumed by `initialize` |

## Authority model (capabilities)

Authority is held by **bearer capability objects**, not hardcoded addresses:

- **AdminCap** → `update_config`, `update_maintenance`, `init_registry`.
- **RelayerCap** → `verdict_action`.
- **owner** (sender == `agent.owner`) → register, activate/deactivate, update target, approve/reject.
- **agent wallet** (sender == `agent.agent_wallet`) → `submit_action`.

Rotate authority by **transferring the cap object** (no redeploy). The `config.operator` /
`config.relayer` address fields are informational only — they are never read in an
authorization check.

### One-time bootstrap (OTW)

`initialize` is gated by a **one-time witness**: at publish, module `init` mints a single
`BootstrapCap` to the deployer; `initialize` consumes it. So the firewall can be initialized
**only by the deployer, exactly once** (enforced by the type system — the cap is destroyed).

## Behaviour

- **Decision mapping**: `raw < escalate → Approved`, `escalate ≤ raw < block → Escalated`,
  `raw ≥ block → Blocked`.
- **EMA reputation**: `next = (alpha*raw + (scale-alpha)*prev) / scale`.
- **Strike**: added when `raw_score ≥ block_threshold` (a Blocked verdict) and when the owner
  rejects an escalated action. Strikes only go up.
- **Auto-deactivate**: when `strikes ≥ max_strikes` the agent is automatically deactivated
  (checked on every verdict).
- **`decision`** is frozen at verdict; `approve`/`reject` change only `status`. The
  `EscalationResolved` event reports the final status.
- **Maintenance gate**: `register`, `submit`, `verdict`, and the agent-lifecycle handlers
  reject while `maintenance = true`. Escalation resolution (`approve`/`reject`) is ungated.
- **Validation**: `initialize` / `update_config` enforce `escalate ≤ block`,
  `ema_scale > 0 && ema_alpha ≤ ema_scale`, and a 32-byte `relayer_encryption_key`.
- **Uniqueness**: per-agent `action_id` uniqueness via the `action_index` table (also serves
  as an `action_id → Action object ID` lookup).

## Lifecycle

1. `initialize` — deployer creates Config + mints `AdminCap` (to deployer) and `RelayerCap`
   (to the relayer address); consumes the `BootstrapCap`.
2. `registry::init_registry` — operator creates the agent registry (one-time bootstrap).
3. `register_agent` — owner registers an agent (records `agent_wallet`, spend limit).
4. `submit_action` — agent wallet submits an encrypted action (status `Pending`).
5. `verdict_action` — relayer writes `raw_score` + `reasoning_hash`; the program decides
   Approved / Escalated / Blocked and updates EMA reputation + strikes.
6. `approve_action` / `reject_action` — owner resolves an `Escalated` action.

## Encryption

The agent SDK encrypts the payload (user prompt + serialized intended transaction) to the
relayer's **x25519 public key** (stored in Config) using **ECDH + ChaCha20-Poly1305**, and
computes a **blake3 commitment** of the plaintext (stored on-chain). Only the relayer can
decrypt; it recomputes the commitment to detect tampering. See `sdk/README.md`.

## Build & test

```bash
cd sui-contract
sui move build
sui move test          # Move unit tests (offline)

# TypeScript SDK / tests
npm install
npm test               # crypto unit tests (offline)
npm run test:e2e       # end-to-end against testnet (needs .env, see sdk/README.md)
```

## Deploy (testnet)

```bash
sui client publish --gas-budget 200000000
```

After publishing, run `initialize` (with the `BootstrapCap` from the publish tx) and
`registry::init_registry`. The current testnet deployment IDs are recorded in
[`DEPLOYMENT.testnet.md`](./DEPLOYMENT.testnet.md).

## Prerequisites

- **Sui CLI** (verified with `sui 1.73.1`)
- **Node.js** ≥ 20 (for the SDK + tests)
