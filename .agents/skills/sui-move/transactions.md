# Programmable Transaction Blocks (PTBs) & sponsored transactions

## PTBs
A Sui transaction is a *block* of commands executed atomically, where the output of one
command can feed the next. From the TypeScript SDK (`@mysten/sui`):

```ts
import { Transaction } from "@mysten/sui/transactions";

const tx = new Transaction();
tx.moveCall({
  target: `${PKG}::action_flow::submit_action`,
  arguments: [
    tx.object(CONFIG_ID),
    tx.object(agentId),
    tx.pure.address(targetProgram),
    tx.pure.u64(value),
    tx.pure.u64(actionId),
    tx.pure.vector("u8", encryptedPayload),
    tx.pure.vector("u8", commitmentHash),
  ],
});
const res = await client.signAndExecuteTransaction({ signer, transaction: tx });
```

Notes:
- `tx.object(id)` for objects (shared or owned); the SDK resolves shared-object versions.
- `tx.pure.<type>(...)` for value arguments. `vector<u8>` → `tx.pure.vector("u8", bytes)`.
- The `&mut TxContext` parameter is implicit — do NOT pass it from the client.
- Read results from the transaction effects / emitted events, not return values.

## Sponsored (gasless) transactions
This is the Sui-native replacement for an on-chain "fee payer / vault sponsor" object.
The **sender** authorizes the action; a **sponsor** pays the gas.

Flow:
1. Build the tx with the user as sender (`tx.setSender(userAddress)`).
2. The sponsor sets the gas payment from *its* coins and signs as gas owner.
3. The user signs the same tx bytes.
4. Submit both signatures.

```ts
tx.setSender(userAddr);
tx.setGasOwner(sponsorAddr);
const bytes = await tx.build({ client });
const userSig = (await userKeypair.signTransaction(bytes)).signature;
const sponsorSig = (await sponsorKeypair.signTransaction(bytes)).signature;
await client.executeTransactionBlock({ transactionBlock: bytes, signature: [userSig, sponsorSig] });
```

Use this so the agent wallet can `submit_action` without holding SUI for gas — the relayer
sponsors it. No on-chain code is required for sponsorship.

## Shared-object contention
Mutations to the same shared object are sequenced. High-frequency writers to one shared
object can bottleneck — prefer per-entity objects (one `Action` per action, as done here)
over a single global mutable object.
