/// Shared, package-wide constants.
///
/// Move constants are module-private and cannot be read from another module, so
/// values that several modules need are exposed here as small public accessor
/// functions (the idiomatic Sui workaround).
module levi::constants;

/// Max encrypted payload per action, in bytes.
const MAX_PAYLOAD: u64 = 8192;

/// Max inline allowed-target whitelist entries.
const MAX_ALLOWED_TARGETS: u64 = 10;

public fun max_payload(): u64 { MAX_PAYLOAD }

public fun max_allowed_targets(): u64 { MAX_ALLOWED_TARGETS }
