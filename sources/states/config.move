/// `Config` state — the shared singleton holding relayer identity, encryption key,
/// policy thresholds and EMA parameters.
///
/// This module owns the `Config` struct and therefore all field access. Handlers in
/// other modules (`initialize`, `update_config`, `update_maintenance`) drive it through
/// the `public(package)` operations below; reads go through the getters.
module levi::config;

use levi::events;

public struct Config has key {
    id: UID,
    operator: address,
    relayer: address,
    relayer_encryption_key: vector<u8>,
    escalate_threshold: u32,
    block_threshold: u32,
    max_strikes: u8,
    ema_alpha: u16,
    ema_scale: u16,
    total_agents: u64,
    maintenance: bool,
}

#[error]
const EInMaintenance: vector<u8> = b"Levi is in maintenance mode";

#[error]
const EInvalidThresholds: vector<u8> = b"escalate_threshold must be <= block_threshold";

#[error]
const EInvalidEmaParams: vector<u8> = b"ema_scale must be > 0 and ema_alpha <= ema_scale";

#[error]
const EInvalidEncryptionKey: vector<u8> = b"relayer_encryption_key must be 32 bytes (x25519)";

/// x25519 public key length (32 bytes).
const ENCRYPTION_KEY_LEN: u64 = 32;

// ----- Package operations (driven by handlers) -----

/// Create the shared `Config`, emit `InitializeConfig`, and return its id.
/// Validates that `escalate_threshold <= block_threshold`.
public(package) fun create_and_share(
    operator: address,
    relayer: address,
    relayer_encryption_key: vector<u8>,
    escalate_threshold: u32,
    block_threshold: u32,
    max_strikes: u8,
    ema_alpha: u16,
    ema_scale: u16,
    ctx: &mut TxContext,
): ID {
    assert!(escalate_threshold <= block_threshold, EInvalidThresholds);
    assert!(ema_scale > 0 && ema_alpha <= ema_scale, EInvalidEmaParams);
    assert!(vector::length(&relayer_encryption_key) == ENCRYPTION_KEY_LEN, EInvalidEncryptionKey);

    let config = Config {
        id: object::new(ctx),
        operator,
        relayer,
        relayer_encryption_key,
        escalate_threshold,
        block_threshold,
        max_strikes,
        ema_alpha,
        ema_scale,
        total_agents: 0,
        maintenance: false,
    };
    let config_id = object::id(&config);

    transfer::share_object(config);
    events::emit_initialize_config(config_id, operator, relayer);
    config_id
}

/// Apply an optional subset of updates. Each `none` leaves the field unchanged.
/// Re-validates thresholds afterwards and emits `UpdateConfig`.
public(package) fun apply_update(
    config: &mut Config,
    mut new_relayer: Option<address>,
    mut new_encryption_key: Option<vector<u8>>,
    mut new_escalate_threshold: Option<u32>,
    mut new_block_threshold: Option<u32>,
    mut new_max_strikes: Option<u8>,
    mut new_ema_alpha: Option<u16>,
    mut new_ema_scale: Option<u16>,
) {
    if (new_relayer.is_some()) { config.relayer = new_relayer.extract(); };
    new_relayer.destroy_none();

    if (new_encryption_key.is_some()) {
        let key = new_encryption_key.extract();
        assert!(vector::length(&key) == ENCRYPTION_KEY_LEN, EInvalidEncryptionKey);
        config.relayer_encryption_key = key;
    };
    new_encryption_key.destroy_none();

    if (new_escalate_threshold.is_some()) { config.escalate_threshold = new_escalate_threshold.extract(); };
    new_escalate_threshold.destroy_none();

    if (new_block_threshold.is_some()) { config.block_threshold = new_block_threshold.extract(); };
    new_block_threshold.destroy_none();

    if (new_max_strikes.is_some()) { config.max_strikes = new_max_strikes.extract(); };
    new_max_strikes.destroy_none();

    if (new_ema_alpha.is_some()) { config.ema_alpha = new_ema_alpha.extract(); };
    new_ema_alpha.destroy_none();

    if (new_ema_scale.is_some()) { config.ema_scale = new_ema_scale.extract(); };
    new_ema_scale.destroy_none();

    assert!(config.escalate_threshold <= config.block_threshold, EInvalidThresholds);
    assert!(config.ema_scale > 0 && config.ema_alpha <= config.ema_scale, EInvalidEmaParams);
    events::emit_update_config(object::id(config));
}

/// Toggle the maintenance flag and emit `MaintenanceUpdated`.
public(package) fun set_maintenance(config: &mut Config, on: bool) {
    config.maintenance = on;
    events::emit_maintenance_updated(object::id(config), on);
}

/// Abort if the firewall is in maintenance. Called at the top of mutating handlers.
public(package) fun assert_not_maintenance(config: &Config) {
    assert!(!config.maintenance, EInMaintenance);
}

/// Bump the registered-agent counter (called by `register_agent`).
public(package) fun increment_agents(config: &mut Config) {
    config.total_agents = config.total_agents + 1;
}

// ----- Getters -----

public fun operator(config: &Config): address { config.operator }

public fun relayer(config: &Config): address { config.relayer }

public fun relayer_encryption_key(config: &Config): vector<u8> { config.relayer_encryption_key }

public fun escalate_threshold(config: &Config): u32 { config.escalate_threshold }

public fun block_threshold(config: &Config): u32 { config.block_threshold }

public fun max_strikes(config: &Config): u8 { config.max_strikes }

public fun ema_alpha(config: &Config): u16 { config.ema_alpha }

public fun ema_scale(config: &Config): u16 { config.ema_scale }

public fun total_agents(config: &Config): u64 { config.total_agents }

public fun is_maintenance(config: &Config): bool { config.maintenance }
