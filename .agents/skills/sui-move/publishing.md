# Publish & upgrade a package

## Prerequisites
- `sui` CLI on PATH (this project verified with `sui 1.73.1`).
- An active environment + funded address:
```bash
sui client active-env
sui client active-address
sui client faucet            # devnet/testnet gas
```

## Build / test before publishing
```bash
sui move build
sui move test
```
`Move.lock` pins the framework revision and **should be committed**. `build/` is generated
and git-ignored.

## Publish
```bash
sui client publish --gas-budget 200000000
```
From the output, record:
- **packageId** — the published address (replaces `levi = "0x0"` at runtime).
- **created objects** — your shared singletons and capabilities, e.g. the `AdminCap` /
  `RelayerCap` (sent to the deployer/relayer) and, after you call `initialize` /
  `init_registry`, the `Config` and `AgentRegistry` shared objects.

Then run the bootstrap transactions:
1. `initialize::initialize(relayer, enc_key, escalate, block, max_strikes, alpha, scale)`
2. `registry::init_registry(&AdminCap)`

## Addresses in Move.toml
- Development: `levi = "0x0"`.
- After publish, for downstream packages or scripts you reference the concrete
  `packageId`; you may add `published-at = "0x<id>"` under `[package]` for upgrades.

## Upgrades
Sui packages are upgradeable via the `UpgradeCap` minted at publish:
```bash
sui client upgrade --upgrade-capability <UpgradeCap-ID> --gas-budget 200000000
```
Rules: you may add new functions/structs and new modules, but cannot change existing
function signatures or struct layouts incompatibly. Plan storage with this in mind
(reserve padding / use dynamic fields for fields you may add later).

## Common pitfalls
- Forgetting to run the bootstrap (`initialize` + `init_registry`) after publish.
- Hardcoding `0x0` in the SDK — always read the real `packageId` from publish output.
- Losing the `AdminCap` / `UpgradeCap` — back up the addresses that received them.
