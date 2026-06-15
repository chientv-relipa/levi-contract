/// Handler: add a new whitelist entry or toggle an existing target's `allowed` flag
/// (owner only). Mirrors Solana `update_agent_program_target.rs`. Maintenance-gated.
module levi::update_agent_program_target;

use levi::config::{Self, Config};
use levi::agent::{Self, Agent};

#[error]
const ENotOwner: vector<u8> = b"caller is not the agent owner";

public fun update_agent_program_target(
    config: &Config,
    agent: &mut Agent,
    target: address,
    allowed: bool,
    ctx: &TxContext,
) {
    config::assert_not_maintenance(config);
    assert!(ctx.sender() == agent::owner(agent), ENotOwner);
    agent::add_or_update_target(agent, target, allowed);
}
