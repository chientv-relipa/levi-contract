# Levi — AI Agent Firewall on Sui (Move)

Levi is an on-chain firewall for AI agents on Sui. It intercepts the actions an agent
wants to broadcast, stores the encrypted intent on-chain, has an independent LLM relayer
analyze it off-chain, and only lets the action execute once a verdict allows it.

This is the Sui/Move port of the Solana reference implementation in the sibling
`../contract/` package. Levi keeps the business architecture (gatekeeper, second-LLM
analysis, reputation/strikes, escalation, payload encryption) but **drops the
Solana-specific infrastructure** — MagicBlock Ephemeral Rollup, delegation/commit, vault
sponsor, chunked writes — because Sui is natively fast and supports sponsored transactions.

The Move **package name is `contract`** (mirrors the Solana side) while the on-chain
**module namespace is `levi`** (the product name on Sui).

## Layout

The package is split into many small, single-responsibility modules, organised in
folders that mirror the Solana reference (`common/`, `states/`, `handlers/`). Note a
Move language rule: **one module = one file**, and **constants (incl. error codes) are
module-private** — they cannot be shared from a single `errors` module, so each
`#[error]` lives in the module that raises it.

```
sui-contract/
├── Move.toml                      # package `contract`, edition 2024, address `levi`
├── sources/
│   ├── common/
│   │   ├── constants.move         # MAX_PAYLOAD, MAX_ALLOWED_TARGETS (public accessors)
│   │   └── events.move            # shared event schema + emit_* helpers
│   ├── states/                    # data objects + their package-internal operations
│   │   ├── capability.move        # AdminCap, RelayerCap (authority objects)
│   │   ├── config.move            # Config singleton: fields, getters, create/update ops
│   │   ├── registry.move          # AgentRegistry: Table<wallet, Agent ID>
│   │   ├── agent.move             # Agent: identity, policy, whitelist, reputation
│   │   └── action.move            # Action: status codes, guards, verdict mutators
│   └── handlers/                  # entry functions — ONE MODULE PER INSTRUCTION
│       ├── initialize.move                  # bootstrap: create Config + mint caps
│       ├── update_config.move               # update_config (AdminCap)
│       ├── update_maintenance.move          # update_maintenance (AdminCap)
│       ├── register_agent.move              # register_agent (sender = owner)
│       ├── activate_agent.move              # activate_agent (owner)
│       ├── deactivate_agent.move            # deactivate_agent (owner)
│       ├── update_agent_program_target.move # whitelist add/toggle (owner)
│       ├── submit_action.move               # submit_action (sender = agent wallet)
│       ├── verdict_action.move              # verdict_action (RelayerCap)
│       ├── approve_action.move              # approve_action (owner)
│       └── reject_action.move               # reject_action (owner)
└── tests/                         # Move unit / scenario tests (32 tests)
```

### Module responsibilities

| Layer | Module | Mirrors Solana |
|-------|--------|----------------|
| common | `constants` | `common/constant.rs` |
| common | `events` | `common/event.rs` |
| states | `capability` | the `OPERATOR_PUBKEY` / `config.relayer` checks |
| states | `config` | `states/config.rs` |
| states | `registry` | the `[b"levi", b"agent", wallet]` PDA lookup |
| states | `agent` | `states/agent.rs` |
| states | `action` | `states/action.rs` |
| handlers | `initialize` | `admin/initialize.rs` |
| handlers | `update_config` | `admin/update_confg.rs` |
| handlers | `update_maintenance` | `admin/update_maintenance.rs` |
| handlers | `register_agent` | `register_agent.rs` |
| handlers | `activate_agent` | `active_agent.rs` |
| handlers | `deactivate_agent` | `deactivate_agent.rs` |
| handlers | `update_agent_program_target` | `update_agent_program_target.rs` |
| handlers | `submit_action` | `init_action.rs` + `append_payload.rs` + `finalize_action_building.rs` (collapsed) |
| handlers | `verdict_action` | `admin/verdict_action.rs` |
| handlers | `approve_action` | `approve_action.rs` |
| handlers | `reject_action` | `reject_action.rs` |

Each handler module is named after its instruction and exposes a single public entry
function of the same name (`levi::submit_action::submit_action`, …), mirroring the
one-file-per-instruction layout of the Solana `contexts/` folder.

## Architecture mapping (Solana → Sui)

| Solana / Anchor | Sui / Move |
|---|---|
| PDA (seeds) | Shared object + `Table` registry |
| `signer == PUBKEY` checks | Capability objects (`AdminCap`, `RelayerCap`) + sender checks |
| Multi-signer instruction | One sender per tx; authority via caps + sponsored gas |
| MagicBlock ER: delegate / commit / vault sponsor | **Removed** (Sui is fast; native sponsored tx) |
| Zero-copy + chunked payload (init→delegate→append→finalize) | Single `submit_action` with `vector<u8>` |
| `emit!(Event)` | `sui::event::emit` |

### Authority model — IMPORTANT (differs from Solana)

In Solana, the `config.operator` / `config.relayer` **address fields ARE the authority**
(every handler checks `signer == config.operator` / `== config.relayer`). In this Sui
port, authority is held by **bearer capability objects**:

- **Admin** authority = whoever holds the `AdminCap` (gates `update_config`,
  `update_maintenance`).
- **Relayer** authority = whoever holds the `RelayerCap` (gates `verdict_action`).

Consequently the `config.operator` and `config.relayer` fields are **informational only**
— they are stored for off-chain discovery/display and are **never read in any on-chain
authorization check**. This means:

- **Rotating the relayer** = transfer the `RelayerCap` object to the new relayer. Calling
  `update_config(relayer: …)` changes only the displayed address, **not** who can land
  verdicts. Do both together to keep the field truthful.
- **Rotating the admin** = transfer the `AdminCap` object. There is no `operator` field in
  `update_config` at all.

## Behaviour notes (parity with the Solana reference)

- **Decision mapping** (`decision_for`): `raw < escalate → Approved`,
  `escalate ≤ raw < block → Escalated`, `raw ≥ block → Blocked`.
- **Strike on verdict**: added only when `raw_score ≥ block_threshold` (i.e. Blocked).
- **Strike on reject**: `reject_action` adds a strike and may auto-deactivate the agent —
  matching the Solana `reject_action` (this is fixed here vs. an earlier port that did not
  strike on reject).
- **EMA reputation**: `next = (alpha*raw + (scale-alpha)*prev) / scale`.
- **Auto-deactivate** when `strikes ≥ max_strikes`.
- **`decision` field is frozen at verdict** (Approved/Escalated/Blocked) and is *not*
  overwritten by `approve`/`reject` — same as Solana, where escalation resolution changes
  only `status`. The `EscalationResolved` event reports the final `status`.
- **Maintenance gating** applies to all mutating handlers (`register`, `submit`, `verdict`,
  and the agent lifecycle), matching Solana. Escalation resolution (`approve`/`reject`) is
  intentionally ungated, also matching Solana.

### Intentional divergences from Solana (improvements)

These are stricter/safer than the Solana reference; kept on purpose:

- `submit_action` rejects an **inactive** agent (`EAgentInactive`); Solana does not gate this.
- `submit_action` increments `total_actions` / `action_counter`; in Solana these counters
  are never written (effectively dead fields).
- `initialize` / `update_config` validate `escalate_threshold ≤ block_threshold`
  (`EInvalidThresholds`); Solana does not validate.
- `initialize` / `update_config` validate the EMA params (`ema_scale > 0` and
  `ema_alpha ≤ ema_scale`, `EInvalidEmaParams`). Without this a misconfigured Config would
  underflow `scale - alpha` or divide by zero in `apply_threat_score`, aborting **every**
  verdict. Solana shares the latent bug but does not guard against it.
- `submit_action` enforces **per-agent `action_id` uniqueness** via an `action_index`
  (`Table<u64, ID>`) on the `Agent` (`EDuplicateActionId`). On Solana the
  `[.., "action", agent, action_id]` PDA seed made duplicates impossible for free; Sui has
  no PDA derivation, so the table both restores that guarantee and provides an
  `action_id → Action object ID` lookup (`agent::action_object_id`).

## Lifecycle

1. `initialize::initialize` — operator deploys Config, gets `AdminCap`; relayer gets `RelayerCap`.
2. `registry::init_registry` — operator creates the agent registry (one-time bootstrap).
3. `agent_manager::register_agent` — owner registers an agent (records `agent_wallet`, spend limit).
4. `action_flow::submit_action` — agent wallet submits an encrypted action (status `Pending`).
5. `action_flow::verdict_action` — relayer writes `raw_score` + `reasoning_hash`; the program
   decides Approved / Escalated / Blocked, updates EMA + strikes.
6. `action_flow::approve_action` / `reject_action` — owner resolves an `Escalated` action.

## Prerequisites

- **Sui CLI** — verified with `sui 1.73.1`.
- **Node.js** ≥ 20 (for a future SDK / scripts).

## Build & test

```bash
cd sui-contract
sui move build
sui move test
```

## Publish (testnet)

```bash
cd sui-contract
sui client publish --gas-budget 200000000
```
