/// Handler: reactivate a deactivated agent (owner only).
/// Aborts if the agent is already active. Maintenance-gated.
module levi::activate_agent;

use levi::config::{Self, Config};
use levi::agent::{Self, Agent};
use levi::events;

#[error]
const ENotOwner: vector<u8> = b"caller is not the agent owner";

#[error]
const EAgentAlreadyActive: vector<u8> = b"agent is already active";

public fun activate_agent(config: &Config, agent: &mut Agent, ctx: &TxContext) {
    config::assert_not_maintenance(config);
    assert!(ctx.sender() == agent::owner(agent), ENotOwner);
    assert!(!agent::is_active(agent), EAgentAlreadyActive);
    agent::set_active(agent, true);
    events::emit_active_agent(object::id(agent));
}
