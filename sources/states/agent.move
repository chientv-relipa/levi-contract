/// `Agent` state — identity, policy, inline allowed-target whitelist and reputation.
///
/// The `Agent` is a shared object so its reputation is publicly readable (it IS the
/// public reputation record). This module owns the struct and exposes `public(package)`
/// operations; the lifecycle handlers (`register_agent`, `activate_agent`,
/// `deactivate_agent`, `update_agent_program_target`) and the reputation mutators
/// (`verdict_action`, `reject_action`) drive it through those operations.
module levi::agent;

use sui::table::{Self, Table};
use levi::constants;

public struct AllowedTarget has store, copy, drop {
    target: address,
    allowed: bool,
}

public struct Agent has key {
    id: UID,
    agent_wallet: address,
    owner: address,
    // Policy
    spend_limit: u64,
    // Reputation
    threat_score: u32,
    strikes: u8,
    allowed_targets: vector<AllowedTarget>,
    active: bool,
    // Metadata
    registered_at: u64,
    action_counter: u64,
    total_actions: u64,
    total_approved: u64,
    total_blocked: u64,
    total_escalated: u64,
    // Submitted action_id -> Action object ID. Enforces per-agent action_id uniqueness
    // (table::add aborts on a duplicate key) and doubles as an action_id -> Action lookup.
    action_index: Table<u64, ID>,
}

#[error]
const EAllowedTargetsFull: vector<u8> = b"allowed_targets whitelist is full";

// ----- Construction (driven by agent_manager) -----

/// Create a new active `Agent`, share it, and return its id.
public(package) fun create_and_share(
    owner: address,
    agent_wallet: address,
    spend_limit: u64,
    ctx: &mut TxContext,
): ID {
    let agent = Agent {
        id: object::new(ctx),
        agent_wallet,
        owner,
        spend_limit,
        threat_score: 0,
        strikes: 0,
        allowed_targets: vector[],
        active: true,
        registered_at: ctx.epoch_timestamp_ms(),
        action_counter: 0,
        total_actions: 0,
        total_approved: 0,
        total_blocked: 0,
        total_escalated: 0,
        action_index: table::new(ctx),
    };
    let agent_id = object::id(&agent);
    transfer::share_object(agent);
    agent_id
}

// ----- Whitelist -----

/// Add a new whitelist entry or update an existing target's `allowed` flag.
/// Aborts if adding a new entry past `MAX_ALLOWED_TARGETS`.
public(package) fun add_or_update_target(agent: &mut Agent, target: address, allowed: bool) {
    let n = vector::length(&agent.allowed_targets);
    let mut i = 0;
    let mut found = false;
    while (i < n) {
        let entry = vector::borrow_mut(&mut agent.allowed_targets, i);
        if (entry.target == target) {
            entry.allowed = allowed;
            found = true;
            break
        };
        i = i + 1;
    };

    if (!found) {
        assert!(n < constants::max_allowed_targets(), EAllowedTargetsFull);
        vector::push_back(&mut agent.allowed_targets, AllowedTarget { target, allowed });
    };
}

// ----- Reputation / state mutators (package) -----

public(package) fun set_active(agent: &mut Agent, active: bool) {
    agent.active = active;
}

/// EMA update: `next = (alpha*raw + (scale-alpha)*prev) / scale`.
public(package) fun apply_threat_score(
    agent: &mut Agent,
    raw_score: u32,
    ema_alpha: u16,
    ema_scale: u16,
) {
    let alpha = ema_alpha as u64;
    let scale = ema_scale as u64;
    let prev = agent.threat_score as u64;
    let raw = raw_score as u64;
    let next = (alpha * raw + (scale - alpha) * prev) / scale;
    agent.threat_score = next as u32;
}

/// Add one strike (saturating at u8 max). Strikes only ever go up.
public(package) fun add_strike(agent: &mut Agent) {
    if (agent.strikes < 255) {
        agent.strikes = agent.strikes + 1;
    };
}

/// Auto-deactivate when strikes hit the limit. Returns true if it just deactivated.
public(package) fun auto_deactivate_if_max_strikes(agent: &mut Agent, max_strikes: u8): bool {
    if (agent.strikes >= max_strikes && agent.active) {
        agent.active = false;
        true
    } else {
        false
    }
}

public(package) fun record_approved(agent: &mut Agent) {
    agent.total_approved = agent.total_approved + 1;
}

public(package) fun record_escalated(agent: &mut Agent) {
    agent.total_escalated = agent.total_escalated + 1;
}

public(package) fun record_blocked(agent: &mut Agent) {
    agent.total_blocked = agent.total_blocked + 1;
}

public(package) fun increment_total_actions(agent: &mut Agent) {
    agent.total_actions = agent.total_actions + 1;
}

/// Monotonic high-water mark of the largest action id seen.
public(package) fun increase_action_counter(agent: &mut Agent, current_action_id: u64) {
    if (agent.action_counter < current_action_id) {
        agent.action_counter = current_action_id;
    };
}

/// Record a freshly created action: maps its `action_id` to the Action object ID.
/// Caller must first check `has_action` — `table::add` aborts on a duplicate key,
/// which is the uniqueness guarantee we want.
public(package) fun record_action(agent: &mut Agent, action_id: u64, action_obj_id: ID) {
    table::add(&mut agent.action_index, action_id, action_obj_id);
}

// ----- Getters -----

public fun agent_wallet(agent: &Agent): address { agent.agent_wallet }

public fun owner(agent: &Agent): address { agent.owner }

public fun spend_limit(agent: &Agent): u64 { agent.spend_limit }

public fun threat_score(agent: &Agent): u32 { agent.threat_score }

public fun strikes(agent: &Agent): u8 { agent.strikes }

public fun is_active(agent: &Agent): bool { agent.active }

public fun registered_at(agent: &Agent): u64 { agent.registered_at }

public fun action_counter(agent: &Agent): u64 { agent.action_counter }

public fun total_actions(agent: &Agent): u64 { agent.total_actions }

public fun total_approved(agent: &Agent): u64 { agent.total_approved }

public fun total_escalated(agent: &Agent): u64 { agent.total_escalated }

public fun total_blocked(agent: &Agent): u64 { agent.total_blocked }

public fun allowed_targets_count(agent: &Agent): u64 { vector::length(&agent.allowed_targets) }

/// True if an action with `action_id` has already been submitted for this agent.
public fun has_action(agent: &Agent, action_id: u64): bool {
    table::contains(&agent.action_index, action_id)
}

/// The Action object ID recorded for `action_id` (aborts if none — call `has_action`
/// first). Lets clients/relayer resolve an Action object from `(agent, action_id)`.
public fun action_object_id(agent: &Agent, action_id: u64): ID {
    *table::borrow(&agent.action_index, action_id)
}

/// True if `target` is present in the whitelist and currently allowed.
public fun is_target_allowed(agent: &Agent, target: address): bool {
    let n = vector::length(&agent.allowed_targets);
    let mut i = 0;
    while (i < n) {
        let entry = vector::borrow(&agent.allowed_targets, i);
        if (entry.target == target) {
            return entry.allowed
        };
        i = i + 1;
    };
    false
}
