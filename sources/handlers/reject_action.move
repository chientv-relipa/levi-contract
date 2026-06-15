/// Handler: owner rejects an escalated action (`Escalated → Rejected`).
/// A rejection earns a strike and can auto-deactivate the agent — an owner rejecting an
/// escalated action is itself a negative signal. This is why `reject_action` takes
/// `&Config` + `&mut Agent` while `approve_action` does not. Intentionally ungated for
/// maintenance.
module levi::reject_action;

use levi::config::{Self, Config};
use levi::agent::{Self, Agent};
use levi::action::{Self, Action};
use levi::events;

#[error]
const ENotOwner: vector<u8> = b"caller is not the agent owner";

public fun reject_action(config: &Config, agent: &mut Agent, action: &mut Action, ctx: &TxContext) {
    assert!(ctx.sender() == agent::owner(agent), ENotOwner);
    let agent_id = object::id(agent);
    action::assert_belongs(action, agent_id);
    action::assert_escalated(action);

    action::set_status(action, action::status_rejected());

    // `decision` stays frozen at the verdict value (Escalated); the event reports the
    // final lifecycle status (Rejected).
    events::emit_escalation_resolved(
        action::action_id(action),
        agent_id,
        action::status_rejected(),
        agent::owner(agent),
    );

    agent::add_strike(agent);
    events::emit_strike_added(agent_id, agent::strikes(agent), action::raw_score(action));
    if (agent::auto_deactivate_if_max_strikes(agent, config::max_strikes(config))) {
        events::emit_agent_auto_deactivated(agent_id, agent::threat_score(agent), agent::strikes(agent));
    };
}
