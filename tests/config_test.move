#[test_only]
module levi::config_test;

use levi::initialize;
use levi::update_config;
use levi::update_maintenance;
use levi::config::{Self, Config};
use levi::capability::{AdminCap, RelayerCap};
use sui::test_scenario as ts;

const OPERATOR: address = @0xA;
const RELAYER: address = @0xB;

fun init_config(sc: &mut ts::Scenario) {
    let cap = initialize::new_bootstrap_for_testing(sc.ctx());
    initialize::initialize(
        cap,
        RELAYER,
        b"enc-key-32-bytes-placeholder____",
        40_000,
        70_000,
        5,
        300,
        1_000,
        sc.ctx(),
    );
}

#[test]
fun initialize_sets_fields_and_caps() {
    let mut sc = ts::begin(OPERATOR);
    init_config(&mut sc);

    // Config is shared and carries the supplied policy.
    sc.next_tx(OPERATOR);
    {
        let cfg = sc.take_shared<Config>();
        assert!(config::operator(&cfg) == OPERATOR, 0);
        assert!(config::relayer(&cfg) == RELAYER, 1);
        assert!(config::escalate_threshold(&cfg) == 40_000, 2);
        assert!(config::block_threshold(&cfg) == 70_000, 3);
        assert!(config::max_strikes(&cfg) == 5, 4);
        assert!(config::ema_alpha(&cfg) == 300, 5);
        assert!(config::ema_scale(&cfg) == 1_000, 6);
        assert!(config::total_agents(&cfg) == 0, 7);
        assert!(!config::is_maintenance(&cfg), 8);
        ts::return_shared(cfg);
    };

    // Operator holds the AdminCap; relayer holds the RelayerCap.
    sc.next_tx(OPERATOR);
    {
        let admin = sc.take_from_sender<AdminCap>();
        sc.return_to_sender(admin);
    };
    sc.next_tx(RELAYER);
    {
        let cap = sc.take_from_sender<RelayerCap>();
        sc.return_to_sender(cap);
    };

    ts::end(sc);
}

#[test]
fun update_config_changes_only_provided_subset() {
    let mut sc = ts::begin(OPERATOR);
    init_config(&mut sc);

    sc.next_tx(OPERATOR);
    {
        let admin = sc.take_from_sender<AdminCap>();
        let mut cfg = sc.take_shared<Config>();

        update_config::update_config(
            &admin,
            &mut cfg,
            option::none(),
            option::none(),
            option::some<u32>(50_000),
            option::none(),
            option::some<u8>(7),
            option::none(),
            option::none(),
        );

        assert!(config::escalate_threshold(&cfg) == 50_000, 0);
        assert!(config::max_strikes(&cfg) == 7, 1);
        // untouched fields stay the same
        assert!(config::block_threshold(&cfg) == 70_000, 2);
        assert!(config::relayer(&cfg) == RELAYER, 3);

        ts::return_shared(cfg);
        sc.return_to_sender(admin);
    };

    ts::end(sc);
}

#[test]
fun maintenance_toggles() {
    let mut sc = ts::begin(OPERATOR);
    init_config(&mut sc);

    sc.next_tx(OPERATOR);
    {
        let admin = sc.take_from_sender<AdminCap>();
        let mut cfg = sc.take_shared<Config>();

        update_maintenance::update_maintenance(&admin, &mut cfg, true);
        assert!(config::is_maintenance(&cfg), 0);

        update_maintenance::update_maintenance(&admin, &mut cfg, false);
        assert!(!config::is_maintenance(&cfg), 1);

        ts::return_shared(cfg);
        sc.return_to_sender(admin);
    };

    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::config::EInvalidThresholds)]
fun initialize_rejects_bad_thresholds() {
    let mut sc = ts::begin(OPERATOR);
    // escalate (80k) > block (70k) must abort.
    let cap = initialize::new_bootstrap_for_testing(sc.ctx());
    initialize::initialize(cap, RELAYER, b"enc-key-32-bytes-placeholder____", 80_000, 70_000, 5, 300, 1_000, sc.ctx());
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::config::EInvalidEmaParams)]
fun initialize_rejects_alpha_gt_scale() {
    let mut sc = ts::begin(OPERATOR);
    // ema_alpha (1001) > ema_scale (1000) must abort — would underflow `scale - alpha`.
    let cap = initialize::new_bootstrap_for_testing(sc.ctx());
    initialize::initialize(cap, RELAYER, b"enc-key-32-bytes-placeholder____", 40_000, 70_000, 5, 1_001, 1_000, sc.ctx());
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::config::EInvalidEmaParams)]
fun initialize_rejects_zero_scale() {
    let mut sc = ts::begin(OPERATOR);
    // ema_scale = 0 must abort — would divide by zero in apply_threat_score.
    let cap = initialize::new_bootstrap_for_testing(sc.ctx());
    initialize::initialize(cap, RELAYER, b"enc-key-32-bytes-placeholder____", 40_000, 70_000, 5, 0, 0, sc.ctx());
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::config::EInvalidEncryptionKey)]
fun initialize_rejects_bad_key_length() {
    let mut sc = ts::begin(OPERATOR);
    // A non-32-byte encryption key must abort (mirrors Solana's [u8; 32] type guarantee).
    let cap = initialize::new_bootstrap_for_testing(sc.ctx());
    initialize::initialize(cap, RELAYER, b"too-short", 40_000, 70_000, 5, 300, 1_000, sc.ctx());
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::config::EInvalidThresholds)]
fun update_config_rejects_bad_thresholds() {
    let mut sc = ts::begin(OPERATOR);
    init_config(&mut sc);

    sc.next_tx(OPERATOR);
    let admin = sc.take_from_sender<AdminCap>();
    let mut cfg = sc.take_shared<Config>();
    // Raise escalate to 80_000 while block stays 70_000 → escalate > block → abort.
    update_config::update_config(
        &admin,
        &mut cfg,
        option::none(),
        option::none(),
        option::some<u32>(80_000),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
    );
    ts::return_shared(cfg);
    sc.return_to_sender(admin);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::config::EInvalidEncryptionKey)]
fun update_config_rejects_bad_key_length() {
    let mut sc = ts::begin(OPERATOR);
    init_config(&mut sc);

    sc.next_tx(OPERATOR);
    let admin = sc.take_from_sender<AdminCap>();
    let mut cfg = sc.take_shared<Config>();
    // A non-32-byte key via update must abort.
    update_config::update_config(
        &admin,
        &mut cfg,
        option::none(),
        option::some<vector<u8>>(b"short"),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
    );
    ts::return_shared(cfg);
    sc.return_to_sender(admin);
    ts::end(sc);
}

#[test]
#[expected_failure(abort_code = levi::config::EInvalidEmaParams)]
fun update_config_rejects_bad_ema() {
    let mut sc = ts::begin(OPERATOR);
    init_config(&mut sc);

    sc.next_tx(OPERATOR);
    let admin = sc.take_from_sender<AdminCap>();
    let mut cfg = sc.take_shared<Config>();
    // Raise ema_alpha to 2000 while ema_scale stays 1000 → alpha > scale → abort.
    update_config::update_config(
        &admin,
        &mut cfg,
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::none(),
        option::some<u16>(2_000),
        option::none(),
    );
    ts::return_shared(cfg);
    sc.return_to_sender(admin);
    ts::end(sc);
}
