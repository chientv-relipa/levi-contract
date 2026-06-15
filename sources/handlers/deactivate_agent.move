/// Handler: deactivate an agent (owner only).
/// Maintenance-gated.
module levi::deactivate_agent;

use levi::config::{Self, Config};
use levi::agent::{Self, Agent};
use levi::events;

#[error]
const ENotOwner: vector<u8> = b"caller is not the agent owner";

public fun deactivate_agent(config: &Config, agent: &mut Agent, ctx: &TxContext) {
    config::assert_not_maintenance(config);
    assert!(ctx.sender() == agent::owner(agent), ENotOwner);
    agent::set_active(agent, false);
    events::emit_deactivate_agent(object::id(agent));
}
