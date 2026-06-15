/// Handler: submit an encrypted action for analysis (sender = agent wallet).
/// Mirrors Solana `init_action.rs` + `append_payload.rs` + `finalize_action_building.rs`
/// collapsed into one call (Sui has no 1232-byte tx limit, so no chunking is needed).
/// Creates the `Action` in `PENDING` and emits `ActionSubmitted`.
module levi::submit_action;

use levi::constants;
use levi::config::{Self, Config};
use levi::agent::{Self, Agent};
use levi::action;
use levi::events;

#[error]
const ENotAgentWallet: vector<u8> = b"caller is not the agent wallet";

#[error]
const EAgentInactive: vector<u8> = b"agent is not active";

#[error]
const EPayloadTooLarge: vector<u8> = b"encrypted payload exceeds MAX_PAYLOAD";

#[error]
const EDuplicateActionId: vector<u8> = b"action_id already used for this agent";

public fun submit_action(
    config: &Config,
    agent: &mut Agent,
    target_program: address,
    value: u64,
    action_id: u64,
    encrypted_payload: vector<u8>,
    commitment_hash: vector<u8>,
    ctx: &mut TxContext,
) {
    config::assert_not_maintenance(config);
    assert!(ctx.sender() == agent::agent_wallet(agent), ENotAgentWallet);
    assert!(agent::is_active(agent), EAgentInactive);
    assert!(vector::length(&encrypted_payload) <= constants::max_payload(), EPayloadTooLarge);
    assert!(!agent::has_action(agent, action_id), EDuplicateActionId);

    let agent_id = object::id(agent);
    let action_obj_id = action::create_and_share(
        agent_id,
        action_id,
        target_program,
        value,
        commitment_hash,
        encrypted_payload,
        ctx,
    );

    agent::record_action(agent, action_id, action_obj_id);
    agent::increment_total_actions(agent);
    agent::increase_action_counter(agent, action_id);

    events::emit_action_submitted(action_obj_id, agent_id, action_id);
}
