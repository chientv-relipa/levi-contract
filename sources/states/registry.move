/// Agent registry — maps an agent wallet address to its `Agent` object ID.
///
/// Sui has no PDA derivation, so this shared `Table` replaces the Solana
/// `[b"levi", b"agent", wallet]` seed lookup: clients and the relayer resolve an
/// `Agent` object from a wallet address through this registry.
module levi::registry;

use sui::table::{Self, Table};
use levi::capability::AdminCap;

public struct AgentRegistry has key {
    id: UID,
    agents: Table<address, ID>,
}

#[error]
const EAgentAlreadyRegistered: vector<u8> = b"agent wallet already registered";

/// Create and share the singleton registry. Requires the `AdminCap`, so it is part
/// of the operator's one-time bootstrap (run right after `initialize`).
public fun init_registry(_admin: &AdminCap, ctx: &mut TxContext) {
    let registry = AgentRegistry {
        id: object::new(ctx),
        agents: table::new(ctx),
    };
    transfer::share_object(registry);
}

/// Record a new agent. Aborts if the wallet is already registered.
public(package) fun register(registry: &mut AgentRegistry, agent_wallet: address, agent_id: ID) {
    assert!(!table::contains(&registry.agents, agent_wallet), EAgentAlreadyRegistered);
    table::add(&mut registry.agents, agent_wallet, agent_id);
}

public fun contains(registry: &AgentRegistry, agent_wallet: address): bool {
    table::contains(&registry.agents, agent_wallet)
}

public fun get(registry: &AgentRegistry, agent_wallet: address): ID {
    *table::borrow(&registry.agents, agent_wallet)
}

public fun size(registry: &AgentRegistry): u64 {
    table::length(&registry.agents)
}
