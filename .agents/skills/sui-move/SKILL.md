---
name: sui-move
description: Sui Move development patterns. Covers the object model (owned vs shared objects, UID, abilities), the capability authorization pattern, dynamic fields & Table collections, Programmable Transaction Blocks (PTBs) and sponsored transactions, events, the test_scenario unit-testing framework, and package publish/upgrade. Use for building, testing, and shipping Sui Move smart contracts — including porting Solana/Anchor programs to Sui.
user-invocable: true
---

# Sui Move Skill

## What this Skill is for
Use this Skill when the user asks for:
- Designing or implementing Sui Move modules (structs, abilities, entry functions)
- Choosing owned vs shared objects, or replacing Solana PDAs with objects + `Table`
- Authorization design (capability objects vs sender checks)
- Programmable Transaction Blocks (PTBs) and sponsored (gasless) transactions
- Writing `test_scenario` unit tests
- Publishing / upgrading a package on devnet / testnet / mainnet
- Porting a Solana/Anchor program to Sui Move

## Key Concepts

**Objects, not accounts.** Every Sui object has a globally unique `id: UID` and a set of
abilities (`key`, `store`, `copy`, `drop`). State lives in objects; modules are stateless
logic. There is no PDA derivation — you address objects by their `ID`.

**Ownership.** An object is either:
- *Owned* by an address (only the owner can use it as a tx input), or
- *Shared* via `transfer::share_object` (anyone can reference it; mutations are sequenced
  by consensus), or
- *Immutable* / *wrapped* inside another object.
Singletons that many parties read/write (Config, Agent, Action here) are **shared**.

**Ability rule for sharing.** `transfer::share_object` / `transfer::transfer` of a
`key`-only object can only be called inside the module that defines the type. Expose a
`public(package) fun create_and_share(...)` in the state module and call it from handlers.

**Capability pattern.** Authorization is "holding an object", not "being a pubkey". Mint
`AdminCap` / `RelayerCap` once at bootstrap; a function requiring authority takes
`_cap: &AdminCap`. Rotating authority = transferring/re-minting the cap. This replaces
Solana's `signer.key() == PUBKEY` and `has_one` checks.

**One sender per transaction.** Unlike Solana's multi-signer instructions, a Sui tx has a
single sender (plus an optional gas sponsor). Model multi-party authority with capability
arguments + sponsored gas, not co-signers.

**Constants are module-private.** A constant (including an error code) cannot be read from
another module. There is no shared `errors` module — put each `#[error]` where it aborts.

**Collections.** Use `sui::table::Table<K, V>` / `Bag` / dynamic fields for keyed lookup
(e.g. wallet → object ID), replacing Solana's seed-based PDA lookup.

**Events.** `sui::event::emit(MyEvent { .. })` where `MyEvent has copy, drop`. Emit one per
state transition.

## Default stack decisions (opinionated)

1. **Edition 2024**, Sui framework as an implicit system dependency (don't declare it).
2. **`states/` + `handlers/` split:** state modules own structs + `public(package)` ops +
   getters; handler modules are the public entry functions.
3. **Shared objects** for multi-writer singletons; **caps** for authority; **`Table`** for
   lookups.
4. **Sponsored transactions** instead of any on-chain "fee payer" object.

## Operating procedure (how to execute tasks)

### 1. Classify the change
- New state → which module owns the struct? what ability set? owned or shared?
- New behaviour → a handler entry function calling state `public(package)` ops.
- New authority → a capability arg or a `sender` check.

### 2. Respect Move's rules
- Share/transfer key-only objects only in their defining module.
- Don't touch another module's struct fields — add a getter / package mutator.
- Errors co-located with the `assert!` that raises them.

### 3. Build & test every change
```bash
sui move build
sui move test
```
Tests use `sui::test_scenario`: `ts::begin(addr)`, `next_tx`, `take_shared<T>`,
`take_from_sender<T>`, `return_shared`, `ts::end`. Assert expected aborts with
`#[expected_failure(abort_code = module::ECode)]`.

### 4. Publish when ready
```bash
sui client publish --gas-budget 200000000
```
Record the package ID and the created cap / shared-object IDs. Use them in the SDK.

### 5. Deliverables expectations
When you implement changes, provide:
- Exact files changed + diffs
- `sui move build` / `sui move test` output
- Risk notes for anything touching authority, shared-object invariants, or money value

## Progressive disclosure (read when needed)
- Object model, abilities, owned vs shared: [objects.md](objects.md)
- Capability / authorization patterns: [capabilities.md](capabilities.md)
- PTBs & sponsored transactions: [transactions.md](transactions.md)
- Unit testing with test_scenario: [testing.md](testing.md)
- Publish & upgrade a package: [publishing.md](publishing.md)
- Reference links & versions: [resources.md](resources.md)
