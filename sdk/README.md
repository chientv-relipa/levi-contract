# Levi Sui SDK

TypeScript SDK for the Levi Move contract — PTB builders + relayer-compatible
encryption. Port of the Solana **Bento** SDK (`../../contract/sdk/`), adapted for Sui:
object IDs instead of PDAs, `@mysten/sui` PTBs instead of Anchor, capability objects
instead of authority pubkeys. The `crypto/` layer is reused verbatim so one relayer can
serve both chains.

## Layout (mirrors Bento)

```
sdk/
├── common/constants.ts   # MAX_PAYLOAD, status enums, module names, deployed object IDs
├── crypto/               # x25519 + ChaCha20-Poly1305 + blake3 (chain-agnostic)
│   ├── keypair / encrypt / decrypt / commitment / action-payload
├── instructions/         # one builder per instruction → adds a moveCall to a Transaction
├── types/                # parsed Config / Agent / Action shapes
├── utils/                # objects (readers + resolvers) + LeviClient (high-level)
└── index.ts
```

## Quick use

```ts
import { SuiClient, getFullnodeUrl } from "@mysten/sui/client";
import { LeviClient, testnetLeviAddresses, TESTNET_ADDRESSES } from "./sdk";

const client = new SuiClient({ url: getFullnodeUrl("testnet") });
const levi = new LeviClient(client, testnetLeviAddresses(), {
  adminCapId: TESTNET_ADDRESSES.adminCapId,
  relayerCapId: TESTNET_ADDRESSES.relayerCapId,
});

// owner registers an agent
const { agentId } = await levi.registerAgent(ownerSigner, {
  agentWallet, spendLimit: 1_000_000n,
});

// agent wallet submits an encrypted action (the SDK encrypts to the relayer key).
// `actionId` is optional — omit it to auto-assign the agent's next monotonic id.
// submitAction also guards the encrypted payload against MAX_PAYLOAD (8192 bytes).
const { actionObjectId } = await levi.submitAction(agentSigner, {
  agentId, targetProgram, value: 1000n,
  prompt: "swap 50 USDC to SOL", txBytes,
});

// relayer (RelayerCap holder) lands a verdict
await levi.verdict(relayerSigner, { agentId, actionObjectId, rawScore: 5000, reasoning: "safe" });
```

## E2E tests

Live tests against the testnet deployment (`tests-ts/`). They require the operator key:

```bash
cp .env.example .env          # then set OPERATOR_SECRET_KEY (suiprivkey1...)
npm install
npm run test:e2e
```

Without `OPERATOR_SECRET_KEY` the e2e suite skips. The tests register a fresh agent, fund
it, then exercise submit → verdict (approve / escalate / **blocked**) → owner approve /
reject, plus a strike-accumulation run that **auto-deactivates** an agent at `max_strikes`,
asserting on-chain state (status, EMA threat score, strikes, active flag).

Offline crypto/payload unit tests (`tests-ts/crypto.test.ts`) run with `npm test` and need
**no key or network** — they prove the SDK encrypt/commit path matches the relayer's
decrypt/verify path.
