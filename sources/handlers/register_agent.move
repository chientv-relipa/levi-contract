/// Handler: register a new agent (sender = owner).
/// Records `agent_wallet`, marks the agent active, inserts it into the registry and
/// bumps the global agent count.
module levi::register_agent;

use levi::config::{Self, Config};
use levi::registry::{Self, AgentRegistry};
use levi::agent;
use levi::events;

public fun register_agent(
    config: &mut Config,
    registry: &mut AgentRegistry,
    agent_wallet: address,
    spend_limit: u64,
    ctx: &mut TxContext,
) {
    config::assert_not_maintenance(config);

    let owner = ctx.sender();
    let agent_id = agent::create_and_share(owner, agent_wallet, spend_limit, ctx);

    registry::register(registry, agent_wallet, agent_id);
    config::increment_agents(config);
    events::emit_register_agent(agent_id, agent_wallet, owner);
}
