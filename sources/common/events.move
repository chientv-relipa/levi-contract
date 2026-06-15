/// On-chain events emitted across the Levi firewall lifecycle.
///
/// Event structs are defined once here and emitted via package-internal `emit_*`
/// helpers so every module shares a single, consistent event schema. Mirrors the
/// granular event set of the Solana reference (`common/event.rs`).
module levi::events;

use sui::event;

// ----- Config -----

public struct InitializeConfig has copy, drop {
    config_id: ID,
    operator: address,
    relayer: address,
}

public struct UpdateConfig has copy, drop {
    config_id: ID,
}

public struct MaintenanceUpdated has copy, drop {
    config_id: ID,
    maintenance: bool,
}

// ----- Agent lifecycle -----

public struct RegisterAgent has copy, drop {
    agent_id: ID,
    agent_wallet: address,
    owner: address,
}

public struct ActiveAgent has copy, drop {
    agent_id: ID,
}

public struct DeactivateAgent has copy, drop {
    agent_id: ID,
}

// ----- Action flow -----

public struct ActionSubmitted has copy, drop {
    action: ID,
    agent: ID,
    action_id: u64,
}

public struct ActionApproved has copy, drop {
    action: ID,
    agent: ID,
    target_program: address,
    value: u64,
    raw_score: u32,
    threat_score: u32,
}

public struct ActionEscalated has copy, drop {
    action: ID,
    agent: ID,
    target_program: address,
    value: u64,
    raw_score: u32,
    threat_score: u32,
    reasoning_hash: vector<u8>,
}

public struct ActionBlocked has copy, drop {
    action: ID,
    agent: ID,
    target_program: address,
    value: u64,
    raw_score: u32,
    threat_score: u32,
    reasoning_hash: vector<u8>,
}

// ----- Reputation / escalation -----

public struct StrikeAdded has copy, drop {
    agent: ID,
    strikes: u8,
    raw_score: u32,
}

public struct AgentAutoDeactivated has copy, drop {
    agent: ID,
    threat_score: u32,
    strikes: u8,
}

public struct EscalationResolved has copy, drop {
    action_id: u64,
    agent: ID,
    final_decision: u8,
    owner: address,
}

// ----- Emit helpers (package-internal) -----

public(package) fun emit_initialize_config(config_id: ID, operator: address, relayer: address) {
    event::emit(InitializeConfig { config_id, operator, relayer });
}

public(package) fun emit_update_config(config_id: ID) {
    event::emit(UpdateConfig { config_id });
}

public(package) fun emit_maintenance_updated(config_id: ID, maintenance: bool) {
    event::emit(MaintenanceUpdated { config_id, maintenance });
}

public(package) fun emit_register_agent(agent_id: ID, agent_wallet: address, owner: address) {
    event::emit(RegisterAgent { agent_id, agent_wallet, owner });
}

public(package) fun emit_active_agent(agent_id: ID) {
    event::emit(ActiveAgent { agent_id });
}

public(package) fun emit_deactivate_agent(agent_id: ID) {
    event::emit(DeactivateAgent { agent_id });
}

public(package) fun emit_action_submitted(action: ID, agent: ID, action_id: u64) {
    event::emit(ActionSubmitted { action, agent, action_id });
}

public(package) fun emit_action_approved(
    action: ID,
    agent: ID,
    target_program: address,
    value: u64,
    raw_score: u32,
    threat_score: u32,
) {
    event::emit(ActionApproved { action, agent, target_program, value, raw_score, threat_score });
}

public(package) fun emit_action_escalated(
    action: ID,
    agent: ID,
    target_program: address,
    value: u64,
    raw_score: u32,
    threat_score: u32,
    reasoning_hash: vector<u8>,
) {
    event::emit(ActionEscalated {
        action,
        agent,
        target_program,
        value,
        raw_score,
        threat_score,
        reasoning_hash,
    });
}

public(package) fun emit_action_blocked(
    action: ID,
    agent: ID,
    target_program: address,
    value: u64,
    raw_score: u32,
    threat_score: u32,
    reasoning_hash: vector<u8>,
) {
    event::emit(ActionBlocked {
        action,
        agent,
        target_program,
        value,
        raw_score,
        threat_score,
        reasoning_hash,
    });
}

public(package) fun emit_strike_added(agent: ID, strikes: u8, raw_score: u32) {
    event::emit(StrikeAdded { agent, strikes, raw_score });
}

public(package) fun emit_agent_auto_deactivated(agent: ID, threat_score: u32, strikes: u8) {
    event::emit(AgentAutoDeactivated { agent, threat_score, strikes });
}

public(package) fun emit_escalation_resolved(
    action_id: u64,
    agent: ID,
    final_decision: u8,
    owner: address,
) {
    event::emit(EscalationResolved { action_id, agent, final_decision, owner });
}
