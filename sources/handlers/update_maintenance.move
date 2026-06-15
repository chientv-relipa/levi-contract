/// Handler: toggle the maintenance flag, gated on the `AdminCap`.
/// While `true`, every mutating handler rejects with `EInMaintenance`.
module levi::update_maintenance;

use levi::capability::AdminCap;
use levi::config::{Self, Config};

public fun update_maintenance(_admin: &AdminCap, config: &mut Config, on: bool) {
    config::set_maintenance(config, on);
}
