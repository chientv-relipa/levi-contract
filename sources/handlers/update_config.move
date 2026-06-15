/// Handler: update any subset of Config fields, gated on the `AdminCap`.
/// The mutation + validation logic lives in `levi::config`; this is a thin authority
/// wrapper.
module levi::update_config;

use levi::capability::AdminCap;
use levi::config::{Self, Config};

/// Update any subset of config fields. Each `Option` left as `none` is unchanged.
public fun update_config(
    _admin: &AdminCap,
    config: &mut Config,
    new_relayer: Option<address>,
    new_encryption_key: Option<vector<u8>>,
    new_escalate_threshold: Option<u32>,
    new_block_threshold: Option<u32>,
    new_max_strikes: Option<u8>,
    new_ema_alpha: Option<u16>,
    new_ema_scale: Option<u16>,
) {
    config::apply_update(
        config,
        new_relayer,
        new_encryption_key,
        new_escalate_threshold,
        new_block_threshold,
        new_max_strikes,
        new_ema_alpha,
        new_ema_scale,
    );
}
