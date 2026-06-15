# Reference links & versions

## Versions (verified for this project)
- Sui CLI: `1.73.1`
- Move edition: `2024`
- Framework pinned in `Move.lock` (testnet revision)

## Official docs
- Sui docs home: https://docs.sui.io
- The Move Book (Sui): https://move-book.com
- Move concepts (objects, abilities): https://docs.sui.io/concepts/object-model
- Owned vs shared objects: https://docs.sui.io/concepts/object-ownership
- Capabilities pattern: https://move-book.com/programmability/capability.html
- Dynamic fields & Table/Bag: https://docs.sui.io/concepts/dynamic-fields
- Programmable Transaction Blocks: https://docs.sui.io/concepts/transactions/prog-txn-blocks
- Sponsored transactions: https://docs.sui.io/concepts/transactions/sponsored-transactions
- Events: https://docs.sui.io/guides/developer/sui-101/using-events
- Testing (test_scenario): https://docs.sui.io/guides/developer/first-app/build-test
- Package upgrades: https://docs.sui.io/concepts/sui-move-concepts/packages/upgrade

## SDKs / tooling
- TypeScript SDK `@mysten/sui`: https://sdk.mystenlabs.com/typescript
- Sui CLI reference: https://docs.sui.io/references/cli
- suiup (CLI installer): https://docs.sui.io/references/cli

## Standard library / framework packages
- `sui::object`, `sui::transfer`, `sui::tx_context`, `sui::event`
- `sui::table::Table`, `sui::bag::Bag`, `sui::dynamic_field`
- `sui::coin::Coin`, `sui::balance::Balance`, `sui::clock::Clock`
- Hashing: `sui::hash` (`blake2b256`, `keccak256`), `std::hash` (`sha2_256`, `sha3_256`)

## This project
- On-chain package: `../` (`sui-contract`, package `contract`, namespace `levi`)
- Solana reference being ported: `../../contract/`
- Architecture & module map: `../README.md`
