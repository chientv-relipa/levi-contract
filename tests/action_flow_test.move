#[test_only]
module levi::action_flow_test;

use levi::initialize;
use levi::config::Config;
use levi::update_config;
use levi::update_maintenance;
use levi::capability::{AdminCap, RelayerCap};
use levi::registry::{Self, AgentRegistry};
use levi::agent::{Self, Agent};
use levi::register_agent;
use levi::deactivate_agent;
use levi::action::{Self, Action};
use levi::submit_action;
use levi::verdict_action;
use levi::approve_action;
use levi::reject_action;
use sui::test_scenario as ts;

const OPERATOR: address = @0xA;
const RELAYER: address = @0xB;
const OWNER: address = @0xC;
const AGENT_WALLET: address = @0xD;
const STRANGER: address = @0xE;
const TARGET: address = @0x999;

// thresholds: escalate=40_000, block=70_000, max_strikes=5, alpha=300, scale=1_000

/// Deploy Config + Registry and register AGENT_WALLET. Ends on an OWNER tx.
fun bootstrap_and_register(sc: &mut ts::Scenario) {
    let cap = initialize::new_bootstrap_for_testing(sc.ctx());
    initialize::initialize(cap, RELAYER, b"enc-key-32-bytes-placeholder____", 40_000, 70_000, 5, 300, 1_000, sc.ctx());

    sc.next_tx(OPERATOR);
    let admin = sc.take_from_sender<AdminCap>();
    registry::init_registry(&admin, sc.ctx());
    sc.return_to_sender(admin);

    sc.next_tx(OWNER);
    let mut cfg = sc.take_shared<Config>();
    let mut reg = sc.take_shared<AgentRegistry>();
    register_agent::register_agent(&mut cfg, &mut reg, AGENT_WALLET, 1_000_000, sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(reg);
}

/// Submit one action (sender = AGENT_WALLET) with the given id.
fun submit(sc: &mut ts::Scenario, action_id: u64) {
    sc.next_tx(AGENT_WALLET);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    submit_action::submit_action(&cfg, &mut agent, TARGET, 1_000, action_id, b"enc", b"commit", sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);
}

fun big_payload(n: u64): vector<u8> {
    let mut v = vector[];
    let mut i = 0u64;
    while (i < n) {
        vector::push_back(&mut v, 0u8);
        i = i + 1;
    };
    v
}

// ---------- Happy paths ----------

#[test]
fun verdict_approves_low_score() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);

    sc.next_tx(RELAYER);
    {
        let cap = sc.take_from_sender<RelayerCap>();
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        let mut act = sc.take_shared<Action>();

        verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 10_000, b"reason");

        assert!(action::status(&act) == action::status_approved(), 0);
        assert!(action::decision(&act) == action::status_approved(), 1);
        assert!(action::raw_score(&act) == 10_000, 2);
        assert!(agent::total_approved(&agent) == 1, 3);
        assert!(agent::threat_score(&agent) == 3_000, 4); // EMA: 300*10000/1000
        assert!(agent::strikes(&agent) == 0, 5);

        ts::return_shared(cfg);
        ts::return_shared(agent);
        ts::return_shared(act);
        sc.return_to_sender(cap);
    };
    ts::end(sc);
}

#[test]
fun escalated_then_owner_approves() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);

    sc.next_tx(RELAYER);
    {
        let cap = sc.take_from_sender<RelayerCap>();
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        let mut act = sc.take_shared<Action>();
        verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 50_000, b"reason");
        assert!(action::status(&act) == action::status_escalated(), 0);
        assert!(agent::total_escalated(&agent) == 1, 1);
        assert!(agent::strikes(&agent) == 0, 2); // escalate does not strike
        ts::return_shared(cfg);
        ts::return_shared(agent);
        ts::return_shared(act);
        sc.return_to_sender(cap);
    };

    sc.next_tx(OWNER);
    {
        let agent = sc.take_shared<Agent>();
        let mut act = sc.take_shared<Action>();
        approve_action::approve_action(&agent, &mut act, sc.ctx());
        assert!(action::status(&act) == action::status_approved(), 3);
        // `decision` stays frozen at the verdict value (Escalated); status is the final state
        assert!(action::decision(&act) == action::status_escalated(), 4);
        // owner approval does NOT add a strike
        assert!(agent::strikes(&agent) == 0, 5);
        ts::return_shared(agent);
        ts::return_shared(act);
    };
    ts::end(sc);
}

#[test]
fun escalated_then_owner_rejects_and_strikes() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);

    sc.next_tx(RELAYER);
    {
        let cap = sc.take_from_sender<RelayerCap>();
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        let mut act = sc.take_shared<Action>();
        verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 50_000, b"reason");
        assert!(agent::strikes(&agent) == 0, 0); // escalate alone: no strike
        ts::return_shared(cfg);
        ts::return_shared(agent);
        ts::return_shared(act);
        sc.return_to_sender(cap);
    };

    sc.next_tx(OWNER);
    {
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        let mut act = sc.take_shared<Action>();
        reject_action::reject_action(&cfg, &mut agent, &mut act, sc.ctx());
        assert!(action::status(&act) == action::status_rejected(), 1);
        // `decision` stays frozen at the verdict value (Escalated); status is the final state
        assert!(action::decision(&act) == action::status_escalated(), 2);
        // Rejecting an escalated action earns the agent a strike.
        assert!(agent::strikes(&agent) == 1, 3);
        assert!(agent::is_active(&agent), 4); // 1 strike < max
        ts::return_shared(cfg);
        ts::return_shared(agent);
        ts::return_shared(act);
    };
    ts::end(sc);
}

#[test]
fun verdict_blocks_high_score_and_strikes() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);

    sc.next_tx(RELAYER);
    {
        let cap = sc.take_from_sender<RelayerCap>();
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        let mut act = sc.take_shared<Action>();
        verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 80_000, b"reason");
        assert!(action::status(&act) == action::status_blocked(), 0);
        assert!(agent::total_blocked(&agent) == 1, 1);
        assert!(agent::strikes(&agent) == 1, 2);
        assert!(agent::is_active(&agent), 3); // 1 strike < max
        ts::return_shared(cfg);
        ts::return_shared(agent);
        ts::return_shared(act);
        sc.return_to_sender(cap);
    };
    ts::end(sc);
}

#[test]
fun strikes_accumulate_to_auto_deactivate() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);

    // Submit 5 actions while the agent is active.
    let mut k = 0u64;
    while (k < 5) {
        submit(&mut sc, k + 1);
        k = k + 1;
    };

    // Verdict each with a blocking score → 5 strikes → auto-deactivate on the 5th.
    // Resolve each Action object via the agent's action_index (action_id → object ID).
    let mut j = 0u64;
    while (j < 5) {
        sc.next_tx(RELAYER);
        let cap = sc.take_from_sender<RelayerCap>();
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        let id = agent::action_object_id(&agent, j + 1);
        let mut act = ts::take_shared_by_id<Action>(&sc, id);
        verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 80_000, b"reason");
        ts::return_shared(cfg);
        ts::return_shared(agent);
        ts::return_shared(act);
        sc.return_to_sender(cap);
        j = j + 1;
    };

    sc.next_tx(OWNER);
    {
        let agent = sc.take_shared<Agent>();
        assert!(agent::strikes(&agent) == 5, 0);
        assert!(agent::total_blocked(&agent) == 5, 1);
        assert!(!agent::is_active(&agent), 2);
        ts::return_shared(agent);
    };
    ts::end(sc);
}

#[test]
fun lowering_max_strikes_auto_deactivates_on_next_verdict() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);
    submit(&mut sc, 2);
    submit(&mut sc, 3);

    // Two blocking verdicts → 2 strikes, still active under max_strikes = 5.
    let mut j = 1u64;
    while (j <= 2) {
        sc.next_tx(RELAYER);
        let cap = sc.take_from_sender<RelayerCap>();
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        let id = agent::action_object_id(&agent, j);
        let mut act = ts::take_shared_by_id<Action>(&sc, id);
        verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 80_000, b"r");
        ts::return_shared(cfg);
        ts::return_shared(agent);
        ts::return_shared(act);
        sc.return_to_sender(cap);
        j = j + 1;
    };

    // Operator lowers max_strikes from 5 to 2 (5th update_config option = max_strikes).
    sc.next_tx(OPERATOR);
    {
        let admin = sc.take_from_sender<AdminCap>();
        let mut cfg = sc.take_shared<Config>();
        update_config::update_config(
            &admin,
            &mut cfg,
            option::none(),
            option::none(),
            option::none(),
            option::none(),
            option::some<u8>(2),
            option::none(),
            option::none(),
        );
        ts::return_shared(cfg);
        sc.return_to_sender(admin);
    };

    // A NON-blocking (approved) verdict now auto-deactivates: strikes(2) >= max(2).
    sc.next_tx(RELAYER);
    {
        let cap = sc.take_from_sender<RelayerCap>();
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        let id = agent::action_object_id(&agent, 3);
        let mut act = ts::take_shared_by_id<Action>(&sc, id);
        verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 10_000, b"r");
        assert!(action::status(&act) == action::status_approved(), 0);
        assert!(agent::strikes(&agent) == 2, 1); // not a block → no new strike
        assert!(!agent::is_active(&agent), 2);    // but auto-deactivated by the lowered cap
        ts::return_shared(cfg);
        ts::return_shared(agent);
        ts::return_shared(act);
        sc.return_to_sender(cap);
    };
    ts::end(sc);
}

// ---------- Edge cases (expected failures) ----------

#[test]
#[expected_failure(abort_code = levi::config::EInMaintenance)]
fun submit_rejected_in_maintenance() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);

    sc.next_tx(OPERATOR);
    let admin = sc.take_from_sender<AdminCap>();
    let mut cfg = sc.take_shared<Config>();
    update_maintenance::update_maintenance(&admin, &mut cfg, true);
    ts::return_shared(cfg);
    sc.return_to_sender(admin);

    sc.next_tx(AGENT_WALLET);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    submit_action::submit_action(&cfg, &mut agent, TARGET, 1_000, 1, b"e", b"c", sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::submit_action::ENotAgentWallet)]
fun submit_rejected_for_wrong_wallet() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);

    sc.next_tx(STRANGER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    submit_action::submit_action(&cfg, &mut agent, TARGET, 1_000, 1, b"e", b"c", sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::submit_action::EAgentInactive)]
fun submit_rejected_for_inactive_agent() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);

    sc.next_tx(OWNER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    deactivate_agent::deactivate_agent(&cfg, &mut agent, sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);

    sc.next_tx(AGENT_WALLET);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    submit_action::submit_action(&cfg, &mut agent, TARGET, 1_000, 1, b"e", b"c", sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::submit_action::EPayloadTooLarge)]
fun submit_rejected_for_oversized_payload() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);

    sc.next_tx(AGENT_WALLET);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    submit_action::submit_action(&cfg, &mut agent, TARGET, 1_000, 1, big_payload(8_193), b"c", sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::action::EActionNotPending)]
fun verdict_rejected_when_not_pending() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);

    // First verdict approves.
    sc.next_tx(RELAYER);
    let cap = sc.take_from_sender<RelayerCap>();
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    let mut act = sc.take_shared<Action>();
    verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 10_000, b"r");
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::return_shared(act);
    sc.return_to_sender(cap);

    // Second verdict on the same (now Approved) action → abort.
    sc.next_tx(RELAYER);
    let cap = sc.take_from_sender<RelayerCap>();
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    let mut act = sc.take_shared<Action>();
    verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 10_000, b"r");
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::return_shared(act);
    sc.return_to_sender(cap);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::approve_action::ENotOwner)]
fun approve_rejected_for_non_owner() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);

    sc.next_tx(RELAYER);
    let cap = sc.take_from_sender<RelayerCap>();
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    let mut act = sc.take_shared<Action>();
    verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 50_000, b"r"); // escalate
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::return_shared(act);
    sc.return_to_sender(cap);

    // A stranger tries to approve.
    sc.next_tx(STRANGER);
    let agent = sc.take_shared<Agent>();
    let mut act = sc.take_shared<Action>();
    approve_action::approve_action(&agent, &mut act, sc.ctx());
    ts::return_shared(agent);
    ts::return_shared(act);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::submit_action::EDuplicateActionId)]
fun submit_rejected_for_duplicate_action_id() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);
    submit(&mut sc, 1); // same action_id for the same agent → abort
    ts::end(sc);
}

#[test]
fun action_index_records_distinct_ids_and_supports_lookup() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);
    submit(&mut sc, 2);

    sc.next_tx(OWNER);
    {
        let agent = sc.take_shared<Agent>();
        assert!(agent::has_action(&agent, 1), 0);
        assert!(agent::has_action(&agent, 2), 1);
        assert!(!agent::has_action(&agent, 3), 2);
        assert!(agent::total_actions(&agent) == 2, 3);
        // lookup resolves to a live, matching Action object.
        let id1 = agent::action_object_id(&agent, 1);
        let act1 = ts::take_shared_by_id<Action>(&sc, id1);
        assert!(action::action_id(&act1) == 1, 4);
        assert!(action::agent_id(&act1) == object::id(&agent), 5);
        ts::return_shared(act1);
        ts::return_shared(agent);
    };
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::reject_action::ENotOwner)]
fun reject_rejected_for_non_owner() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);

    // Escalate the action first.
    sc.next_tx(RELAYER);
    let cap = sc.take_from_sender<RelayerCap>();
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    let mut act = sc.take_shared<Action>();
    verdict_action::verdict_action(&cap, &cfg, &mut agent, &mut act, 50_000, b"r");
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::return_shared(act);
    sc.return_to_sender(cap);

    // A stranger tries to reject → abort.
    sc.next_tx(STRANGER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    let mut act = sc.take_shared<Action>();
    reject_action::reject_action(&cfg, &mut agent, &mut act, sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::return_shared(act);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::action::EActionNotEscalated)]
fun reject_rejected_when_not_escalated() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);

    // Owner rejects a still-Pending action (never escalated) → abort.
    sc.next_tx(OWNER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    let mut act = sc.take_shared<Action>();
    reject_action::reject_action(&cfg, &mut agent, &mut act, sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::return_shared(act);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::registry::EAgentAlreadyRegistered)]
fun register_rejected_for_duplicate_wallet() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc); // registers AGENT_WALLET once

    // Registering the same wallet again must abort.
    sc.next_tx(OWNER);
    let mut cfg = sc.take_shared<Config>();
    let mut reg = sc.take_shared<AgentRegistry>();
    register_agent::register_agent(&mut cfg, &mut reg, AGENT_WALLET, 1_000_000, sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(reg);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::action::EActionAgentMismatch)]
fun verdict_rejected_for_mismatched_agent() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc); // agent A for AGENT_WALLET
    submit(&mut sc, 1);              // action 1 belongs to agent A

    // Register a second agent B for a different wallet.
    sc.next_tx(OWNER);
    {
        let mut cfg = sc.take_shared<Config>();
        let mut reg = sc.take_shared<AgentRegistry>();
        register_agent::register_agent(&mut cfg, &mut reg, @0xF, 1_000_000, sc.ctx());
        ts::return_shared(cfg);
        ts::return_shared(reg);
    };

    // Relayer applies agent A's action to agent B → mismatch abort (reputation safety).
    sc.next_tx(RELAYER);
    {
        let cap = sc.take_from_sender<RelayerCap>();
        let cfg = sc.take_shared<Config>();
        let reg = sc.take_shared<AgentRegistry>();
        let id_a = registry::get(&reg, AGENT_WALLET);
        let id_b = registry::get(&reg, @0xF);
        let agent_a = ts::take_shared_by_id<Agent>(&sc, id_a);
        let mut agent_b = ts::take_shared_by_id<Agent>(&sc, id_b);
        let act_obj = agent::action_object_id(&agent_a, 1);
        let mut act = ts::take_shared_by_id<Action>(&sc, act_obj);
        verdict_action::verdict_action(&cap, &cfg, &mut agent_b, &mut act, 10_000, b"r");
        ts::return_shared(cfg);
        ts::return_shared(reg);
        ts::return_shared(agent_a);
        ts::return_shared(agent_b);
        ts::return_shared(act);
        sc.return_to_sender(cap);
    };
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::action::EActionNotEscalated)]
fun approve_rejected_when_not_escalated() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap_and_register(&mut sc);
    submit(&mut sc, 1);

    // Owner tries to approve a still-Pending action (never escalated).
    sc.next_tx(OWNER);
    let agent = sc.take_shared<Agent>();
    let mut act = sc.take_shared<Action>();
    approve_action::approve_action(&agent, &mut act, sc.ctx());
    ts::return_shared(agent);
    ts::return_shared(act);
    ts::end(sc);
}
