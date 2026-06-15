# Levi — Testnet Deployment

Network: **Sui testnet**
Operator / deployer: `0x0c8bc50eb0bddb704857c6cc0ff1e8ee4d50e3f009cc43b75138226beb06c2bc`

This is the **v2 deployment** (OTW-gated `initialize` + 32-byte `relayer_encryption_key`
enforcement). The v1 package (`0x4c9ebb…`) is abandoned/orphaned.

## Object IDs

| Name | ID | Type / Owner |
|------|----|--------------|
| Package | `0x5a9e02eabf663e8495a4144e487a71a744c72e378bd9637412c3d45ce69241fb` | Immutable package |
| Config | `0x6f329ff56cd8dad2611a26919872672478ddc6de65fca3a18ed1b3a13e9d995c` | Shared |
| AgentRegistry | `0xbece5badd7e63ef061440268cd0050b04deeb6265253eeec07fe229745557c10` | Shared |
| AdminCap | `0xd845f5a94c2dc5c605918be3035ca614f7442c0dbf1459b7229c99fe5b87bb59` | Owned by operator |
| RelayerCap | `0x4ffe42c13d5ce2db81f0df42f1d43941d8463b10544cc479cc09146cf107e6f7` | Owned by operator |
| UpgradeCap | `0xdf9a8ab6f50d717501d1932b80390d80a0946fd36df4cef3aa4cc31460abd060` | Owned by operator |
| BootstrapCap | consumed (deleted) during `initialize` | — |

## Config values

- relayer = operator address (informational; real relayer authority = RelayerCap; rotate by transferring the cap)
- escalate_threshold = 40000
- block_threshold = 70000
- max_strikes = 5
- ema_alpha = 300, ema_scale = 1000
- relayer_encryption_key — ⚠️ **throwaway 32 zero bytes** (valid length, but no one holds a
  matching secret). The e2e suite overwrites it with a fresh random x25519 key each run
  (secret discarded). The real off-chain relayer MUST set its own persistent x25519 public
  key via `update_config` (now enforced to be exactly 32 bytes).

## Bootstrap transactions (v2)

1. publish (runs OTW `init`, mints BootstrapCap) — `CNNWa7sk3md4t5dH7M3ta8RdgBwfHEqr4Kq5A787S1b8`
2. initialize (consumes BootstrapCap) — `G5hnNc8BtAa5MyJ6mdsGXGe6AB8DCD7PoM1cAaQiiTGk`
3. init_registry — `3mAE156p8pujBi6edFK5DCGmsQaNZVn7XT5Nvpmo7W6q`

## Explorer

- Package: https://suiscan.xyz/testnet/object/0x5a9e02eabf663e8495a4144e487a71a744c72e378bd9637412c3d45ce69241fb

## Authority model (differs from Solana)

`initialize` is one-time-witness gated: at publish, module `init` mints a single
`BootstrapCap` to the deployer; `initialize` consumes it. So bootstrap is deployer-only +
exactly-once (the cap is now deleted — confirmed in tx `G5hnNc8…`). Admin authority =
`AdminCap`; relayer authority = `RelayerCap`. The `config.operator`/`config.relayer`
address fields are informational; rotate authority by transferring the caps.

## TODO before production / off-chain use

- **Set the real relayer encryption key.** Generate a persistent 32-byte x25519 keypair for
  the relayer, keep the secret in the relayer service, and write the public key on-chain via
  `update_config` (length is enforced to 32 bytes).
- If the off-chain relayer uses a separate wallet, transfer `RelayerCap` to it.

## Upgrades

The package can be upgraded with the `UpgradeCap` for **compatible** changes (new
functions/structs, changed function bodies) — package ID changes per version, but shared
objects (Config/Registry) persist. **Incompatible** changes (changed public function
signatures or struct layouts) require a fresh publish + re-bootstrap (as happened for v2,
which changed `initialize`'s signature).
