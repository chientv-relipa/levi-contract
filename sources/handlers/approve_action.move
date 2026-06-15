/// Handler: owner approves an escalated action (`Escalated → Approved`). No strike.
/// Mirrors Solana `approve_action.rs`. Intentionally ungated for maintenance (matches
/// Solana, which does not gate escalation resolution).
module levi::approve_action;

use levi::agent::{Self, Agent};
use levi::action::{Self, Action};
use levi::events;

#[error]
const ENotOwner: vector<u8> = b"caller is not the agent owner";

public fun approve_action(agent: &Agent, action: &mut Action, ctx: &TxContext) {
    assert!(ctx.sender() == agent::owner(agent), ENotOwner);
    action::assert_belongs(action, object::id(agent));
    action::assert_escalated(action);

    action::set_status(action, action::status_approved());

    // `decision` stays frozen at the verdict value (Escalated); the event reports the
    // final lifecycle status (Approved).
    events::emit_escalation_resolved(
        action::action_id(action),
        object::id(agent),
        action::status_approved(),
        agent::owner(agent),
    );
}
