# Capability / authorization patterns

## Why capabilities
On Solana you write `require!(signer.key() == config.relayer)`. On Sui the idiom is:
**holding a capability object is the authority.** No address comparison needed.

```move
public struct AdminCap has key, store { id: UID }
public struct RelayerCap has key, store { id: UID }

public(package) fun mint_admin(ctx: &mut TxContext): AdminCap { AdminCap { id: object::new(ctx) } }
public(package) fun mint_relayer(ctx: &mut TxContext): RelayerCap { RelayerCap { id: object::new(ctx) } }
```

A privileged function simply **takes the cap by reference**:
```move
public fun update_maintenance(_admin: &AdminCap, config: &mut Config, on: bool) { /* ... */ }
public fun verdict_action(_relayer: &RelayerCap, /* ... */) { /* ... */ }
```
The underscore name documents that the cap is a key, not used for data. Possession is
checked by the runtime (you can only pass an object you own).

## Bootstrap (mint once)
Mint caps in the deploy entry function and transfer them to their holders:
```move
public fun initialize(relayer: address, /* ... */, ctx: &mut TxContext) {
    let operator = ctx.sender();
    config::create_and_share(operator, relayer, /* ... */, ctx);
    transfer::public_transfer(capability::mint_admin(ctx), operator);
    transfer::public_transfer(capability::mint_relayer(ctx), relayer);
}
```

## Rotating authority
- Transfer the cap to a new holder, or
- Burn the old cap (delete its `UID`) and mint a fresh one.
No on-chain config field needs to change.

## Owner checks (when a cap is overkill)
For per-object ownership (the agent's human owner), store an `owner: address` field and
check the sender:
```move
assert!(ctx.sender() == agent::owner(agent), ENotOwner);
```
Or mint a per-object `OwnerCap { agent_id: ID }` if you want it transferable.

## Multi-party authority (Solana co-signers → Sui)
A Sui tx has ONE sender + an optional gas sponsor. To require two parties:
- Make one party the sender and require the other's **capability** as an argument, or
- Use a **sponsored transaction** (one pays gas, the other is sender), or
- Split into two sequential transactions.
Do not try to emulate multi-signer instructions directly.
