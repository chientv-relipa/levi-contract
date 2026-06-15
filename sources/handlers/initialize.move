/// Bootstrap entrypoint — creates the shared `Config` and mints the authority caps.
/// Mirrors Solana `admin/initialize.rs` (operator-only, once).
///
/// On Solana those guarantees come from a hardcoded `OPERATOR_PUBKEY` + a singleton
/// PDA. On Sui we use the idiomatic equivalent: a **one-time witness** drives the module
/// `init` (runs exactly once, at publish, for the publisher only), which mints a single
/// `BootstrapCap` to the deployer. `initialize` then **consumes** that cap, so it can be
/// called only by the deployer and only once.
module levi::initialize;

use levi::config;
use levi::capability::{Self, BootstrapCap};

/// One-time witness. Must be the module name in upper case, `drop`-only, no fields.
public struct INITIALIZE has drop {}

/// Runs once at publish. Hands the deployer the single `BootstrapCap`.
fun init(_otw: INITIALIZE, ctx: &mut TxContext) {
    transfer::public_transfer(capability::mint_bootstrap(ctx), ctx.sender());
}

/// `self_transfer` lint is intentionally allowed: delivering the `AdminCap` to the
/// deploying operator (the sender) is the desired bootstrap behaviour.
#[allow(lint(self_transfer))]
public fun initialize(
    bootstrap: BootstrapCap,
    relayer: address,
    relayer_encryption_key: vector<u8>,
    escalate_threshold: u32,
    block_threshold: u32,
    max_strikes: u8,
    ema_alpha: u16,
    ema_scale: u16,
    ctx: &mut TxContext,
) {
    // Consume the one-shot cap first: only the deployer holds it, and it cannot be
    // reused, so initialize is deployer-only + exactly-once.
    capability::consume_bootstrap(bootstrap);

    let operator = ctx.sender();

    // Creates + shares Config and emits InitializeConfig (validates thresholds + EMA).
    config::create_and_share(
        operator,
        relayer,
        relayer_encryption_key,
        escalate_threshold,
        block_threshold,
        max_strikes,
        ema_alpha,
        ema_scale,
        ctx,
    );

    transfer::public_transfer(capability::mint_admin(ctx), operator);
    transfer::public_transfer(capability::mint_relayer(ctx), relayer);
}

/// Test-only: obtain a `BootstrapCap` without going through publish-time `init`.
#[test_only]
public fun new_bootstrap_for_testing(ctx: &mut TxContext): BootstrapCap {
    capability::mint_bootstrap(ctx)
}
