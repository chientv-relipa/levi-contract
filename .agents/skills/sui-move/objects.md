# Object model, abilities, owned vs shared

## Abilities
- `key`   — can be a top-level object (must have `id: UID` as the first field).
- `store` — can be held inside another object, and transferred by any module (`public_transfer`).
- `copy`  — can be duplicated (use for events / value types, never for assets).
- `drop`  — can be discarded without explicit destruction.

Typical combos:
- Shared singleton / asset: `has key` (no `store`) → only the defining module can share/transfer it.
- Capability you hand to a user: `has key, store` → transferable from anywhere.
- Event: `has copy, drop`.
- Inline value struct in a vector: `has store, copy, drop`.

## Owned vs shared
```move
// Shared: many parties read/write; consensus-sequenced.
transfer::share_object(config);

// Owned: only the owner can pass it into a tx.
transfer::public_transfer(admin_cap, recipient); // needs `store`
transfer::transfer(cap, recipient);              // key-only, from defining module
```
Pick **shared** when several actors mutate the same record (Config, Agent, Action).
Pick **owned** for capabilities and per-user assets.

## The sharing rule (important)
`transfer::share_object` / `transfer::transfer` of a `key`-only object can only be called
**inside the module that defines the type**. So state modules expose:
```move
public(package) fun create_and_share(/* fields */, ctx: &mut TxContext): ID {
    let obj = Config { id: object::new(ctx), /* ... */ };
    let id = object::id(&obj);
    transfer::share_object(obj);
    id
}
```
Handlers in other modules call this and never see the raw fields.

## Replacing Solana PDAs
There is no `[seeds]` derivation. Two options:
1. A shared `Table<address, ID>` registry mapping a key (e.g. agent wallet) → object ID.
2. Pass the object's `ID` directly (clients track it from creation events).

This project uses a `registry::AgentRegistry { agents: Table<address, ID> }`.

## Accessing fields across modules
Only the defining module can read/write struct fields. Everyone else uses **getters**
(`public fun owner(a: &Agent): address`) and **package mutators**
(`public(package) fun set_active(a: &mut Agent, b: bool)`).
