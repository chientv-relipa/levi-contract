/// Authority capabilities (replaces Solana's `operator.key() == OPERATOR_PUBKEY` and
/// `relayer.key() == config.relayer` pubkey checks).
///
/// Whoever holds the cap object has the authority. Rotating an authority is just
/// transferring / re-minting the cap. The caps are minted once during `initialize`.
module levi::capability;

/// Admin authority: config / maintenance changes, registry bootstrap.
public struct AdminCap has key, store {
    id: UID,
}

/// Relayer authority: writing verdicts.
public struct RelayerCap has key, store {
    id: UID,
}

/// One-shot bootstrap authority. Minted exactly once to the publisher in the module
/// `init` (see `levi::initialize`) and consumed by `initialize`, so the firewall can be
/// initialized only by the deployer and only once.
public struct BootstrapCap has key, store {
    id: UID,
}

public(package) fun mint_admin(ctx: &mut TxContext): AdminCap {
    AdminCap { id: object::new(ctx) }
}

public(package) fun mint_relayer(ctx: &mut TxContext): RelayerCap {
    RelayerCap { id: object::new(ctx) }
}

public(package) fun mint_bootstrap(ctx: &mut TxContext): BootstrapCap {
    BootstrapCap { id: object::new(ctx) }
}

/// Destroy the bootstrap cap — called by `initialize` so it can never run twice.
public(package) fun consume_bootstrap(cap: BootstrapCap) {
    let BootstrapCap { id } = cap;
    object::delete(id);
}
