#[test_only]
module levi::agent_test;

use levi::initialize;
use levi::update_maintenance;
use levi::config::{Self, Config};
use levi::capability::AdminCap;
use levi::registry::{Self, AgentRegistry};
use levi::agent::{Self, Agent};
use levi::register_agent;
use levi::activate_agent;
use levi::deactivate_agent;
use levi::update_agent_program_target;
use sui::test_scenario as ts;

const OPERATOR: address = @0xA;
const RELAYER: address = @0xB;
const OWNER: address = @0xC;
const AGENT_WALLET: address = @0xD;
const STRANGER: address = @0xE;

/// Deploy Config + Registry (operator bootstrap). Leaves the current tx sender = OPERATOR.
fun bootstrap(sc: &mut ts::Scenario) {
    let cap = initialize::new_bootstrap_for_testing(sc.ctx());
    initialize::initialize(cap, RELAYER, b"enc-key-32-bytes-placeholder____", 40_000, 70_000, 5, 300, 1_000, sc.ctx());
    sc.next_tx(OPERATOR);
    let admin = sc.take_from_sender<AdminCap>();
    registry::init_registry(&admin, sc.ctx());
    sc.return_to_sender(admin);
}

/// Register AGENT_WALLET. Caller must have set the tx sender to OWNER first.
fun register(sc: &mut ts::Scenario, spend_limit: u64) {
    let mut config = sc.take_shared<Config>();
    let mut reg = sc.take_shared<AgentRegistry>();
    register_agent::register_agent(&mut config, &mut reg, AGENT_WALLET, spend_limit, sc.ctx());
    ts::return_shared(config);
    ts::return_shared(reg);
}

#[test]
fun register_creates_agent_and_indexes_it() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(OWNER);
    {
        let cfg = sc.take_shared<Config>();
        let reg = sc.take_shared<AgentRegistry>();
        let agent = sc.take_shared<Agent>();

        assert!(config::total_agents(&cfg) == 1, 0);
        assert!(registry::contains(&reg, AGENT_WALLET), 1);
        assert!(registry::get(&reg, AGENT_WALLET) == object::id(&agent), 2);
        assert!(agent::owner(&agent) == OWNER, 3);
        assert!(agent::agent_wallet(&agent) == AGENT_WALLET, 4);
        assert!(agent::spend_limit(&agent) == 1_000_000, 5);
        assert!(agent::is_active(&agent), 6);
        assert!(agent::threat_score(&agent) == 0, 7);
        assert!(agent::strikes(&agent) == 0, 8);

        ts::return_shared(cfg);
        ts::return_shared(reg);
        ts::return_shared(agent);
    };
    ts::end(sc);
}

#[test]
fun whitelist_add_and_toggle() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(OWNER);
    {
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x111, true, sc.ctx());
        assert!(agent::allowed_targets_count(&agent) == 1, 0);
        assert!(agent::is_target_allowed(&agent, @0x111), 1);

        // toggling an existing target updates in place (no new entry).
        update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x111, false, sc.ctx());
        assert!(agent::allowed_targets_count(&agent) == 1, 2);
        assert!(!agent::is_target_allowed(&agent, @0x111), 3);

        ts::return_shared(cfg);
        ts::return_shared(agent);
    };
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::agent::EAllowedTargetsFull)]
fun whitelist_rejects_overflow() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(OWNER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x101, true, sc.ctx());
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x102, true, sc.ctx());
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x103, true, sc.ctx());
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x104, true, sc.ctx());
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x105, true, sc.ctx());
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x106, true, sc.ctx());
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x107, true, sc.ctx());
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x108, true, sc.ctx());
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x109, true, sc.ctx());
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x10a, true, sc.ctx()); // 10th (full)
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x10b, true, sc.ctx()); // 11th → abort
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
fun deactivate_then_activate() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(OWNER);
    {
        let cfg = sc.take_shared<Config>();
        let mut agent = sc.take_shared<Agent>();
        deactivate_agent::deactivate_agent(&cfg, &mut agent, sc.ctx());
        assert!(!agent::is_active(&agent), 0);
        activate_agent::activate_agent(&cfg, &mut agent, sc.ctx());
        assert!(agent::is_active(&agent), 1);
        ts::return_shared(cfg);
        ts::return_shared(agent);
    };
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::activate_agent::EAgentAlreadyActive)]
fun activate_when_active_aborts() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(OWNER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    activate_agent::activate_agent(&cfg, &mut agent, sc.ctx()); // already active → abort
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::config::EInMaintenance)]
fun lifecycle_rejected_in_maintenance() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    // Operator turns maintenance on.
    sc.next_tx(OPERATOR);
    let admin = sc.take_from_sender<AdminCap>();
    let mut cfg = sc.take_shared<Config>();
    update_maintenance::update_maintenance(&admin, &mut cfg, true);
    ts::return_shared(cfg);
    sc.return_to_sender(admin);

    // Owner tries to deactivate during maintenance → abort (lifecycle handlers are gated).
    sc.next_tx(OWNER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    deactivate_agent::deactivate_agent(&cfg, &mut agent, sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::deactivate_agent::ENotOwner)]
fun non_owner_cannot_deactivate() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(STRANGER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    deactivate_agent::deactivate_agent(&cfg, &mut agent, sc.ctx()); // sender = STRANGER → abort
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::activate_agent::ENotOwner)]
fun non_owner_cannot_activate() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(STRANGER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    activate_agent::activate_agent(&cfg, &mut agent, sc.ctx()); // sender = STRANGER → abort
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::update_agent_program_target::ENotOwner)]
fun non_owner_cannot_update_target() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(STRANGER);
    let cfg = sc.take_shared<Config>();
    let mut agent = sc.take_shared<Agent>();
    update_agent_program_target::update_agent_program_target(&cfg, &mut agent, @0x111, true, sc.ctx());
    ts::return_shared(cfg);
    ts::return_shared(agent);
    ts::end(sc);
}

#[test]
fun reputation_ema_and_counters() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(OWNER);
    {
        let mut agent = sc.take_shared<Agent>();

        // EMA: prev=0, raw=10000, alpha=300, scale=1000 → (300*10000)/1000 = 3000
        agent::apply_threat_score(&mut agent, 10_000, 300, 1_000);
        assert!(agent::threat_score(&agent) == 3_000, 0);
        // again: (300*10000 + 700*3000)/1000 = 5100
        agent::apply_threat_score(&mut agent, 10_000, 300, 1_000);
        assert!(agent::threat_score(&agent) == 5_100, 1);

        agent::add_strike(&mut agent);
        assert!(agent::strikes(&agent) == 1, 2);

        agent::record_approved(&mut agent);
        agent::record_escalated(&mut agent);
        agent::record_blocked(&mut agent);
        agent::increment_total_actions(&mut agent);
        agent::increase_action_counter(&mut agent, 7);
        assert!(agent::total_approved(&agent) == 1, 3);
        assert!(agent::total_escalated(&agent) == 1, 4);
        assert!(agent::total_blocked(&agent) == 1, 5);
        assert!(agent::total_actions(&agent) == 1, 6);
        assert!(agent::action_counter(&agent) == 7, 7);

        ts::return_shared(agent);
    };
    ts::end(sc);
}

#[test]
fun strikes_auto_deactivate_at_max() {
    let mut sc = ts::begin(OPERATOR);
    bootstrap(&mut sc);
    sc.next_tx(OWNER);
    register(&mut sc, 1_000_000);

    sc.next_tx(OWNER);
    {
        let mut agent = sc.take_shared<Agent>();

        let mut i = 0u64;
        while (i < 5) {
            agent::add_strike(&mut agent);
            i = i + 1;
        };
        assert!(agent::strikes(&agent) == 5, 0);

        let deactivated = agent::auto_deactivate_if_max_strikes(&mut agent, 5);
        assert!(deactivated, 1);
        assert!(!agent::is_active(&agent), 2);

        // already inactive → returns false
        let again = agent::auto_deactivate_if_max_strikes(&mut agent, 5);
        assert!(!again, 3);

        ts::return_shared(agent);
    };
    ts::end(sc);
}
