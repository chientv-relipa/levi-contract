/// Handler: the relayer lands a verdict (holder of `RelayerCap`).
/// Mirrors Solana `admin/verdict_action.rs`. Writes `raw_score` + `reasoning_hash`,
/// maps the score to a decision via Config thresholds, then updates the agent's EMA
/// reputation and strikes.
module levi::verdict_action;

use levi::capability::RelayerCap;
use levi::config::{Self, Config};
use levi::agent::{Self, Agent};
use levi::action::{Self, Action};
use levi::events;

public fun verdict_action(
    _relayer: &RelayerCap,
    config: &Config,
    agent: &mut Agent,
    action: &mut Action,
    raw_score: u32,
    reasoning_hash: vector<u8>,
) {
    config::assert_not_maintenance(config);
    let agent_id = object::id(agent);
    action::assert_belongs(action, agent_id);
    action::assert_pending(action);

    let decision = decision_for(config, raw_score);
    action::record_verdict(action, raw_score, reasoning_hash, decision);

    let action_obj_id = object::id(action);
    let target_program = action::target_program(action);
    let value = action::value(action);
    let stored_hash = action::reasoning_hash(action);

    agent::apply_threat_score(
        agent,
        raw_score,
        config::ema_alpha(config),
        config::ema_scale(config),
    );
    let threat_score = agent::threat_score(agent);

    if (decision == action::status_approved()) {
        agent::record_approved(agent);
        events::emit_action_approved(
            action_obj_id,
            agent_id,
            target_program,
            value,
            raw_score,
            threat_score,
        );
    } else if (decision == action::status_escalated()) {
        agent::record_escalated(agent);
        events::emit_action_escalated(
            action_obj_id,
            agent_id,
            target_program,
            value,
            raw_score,
            threat_score,
            stored_hash,
        );
    } else {
        agent::record_blocked(agent);
        events::emit_action_blocked(
            action_obj_id,
            agent_id,
            target_program,
            value,
            raw_score,
            threat_score,
            stored_hash,
        );
    };

    // A blocked action (score at/above the block threshold) earns a strike.
    if (raw_score >= config::block_threshold(config)) {
        agent::add_strike(agent);
        events::emit_strike_added(agent_id, agent::strikes(agent), raw_score);
    };

    // Auto-deactivation is checked on EVERY verdict (matches Solana `verdict_action`,
    // where `auto_deactivate_if_max_strikes` runs unconditionally). This also lets a
    // `max_strikes` later lowered below the agent's current strikes take effect on the
    // next verdict, even one that is not itself a block.
    if (agent::auto_deactivate_if_max_strikes(agent, config::max_strikes(config))) {
        events::emit_agent_auto_deactivated(
            agent_id,
            agent::threat_score(agent),
            agent::strikes(agent),
        );
    };
}

/// Map a raw score to a decision using the Config thresholds.
fun decision_for(config: &Config, raw_score: u32): u8 {
    if (raw_score >= config::block_threshold(config)) {
        action::status_blocked()
    } else if (raw_score >= config::escalate_threshold(config)) {
        action::status_escalated()
    } else {
        action::status_approved()
    }
}
