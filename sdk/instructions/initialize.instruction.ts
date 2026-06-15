import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::initialize::initialize(BootstrapCap, relayer, relayer_encryption_key, escalate,
//   block, max_strikes, ema_alpha, ema_scale). Consumes the BootstrapCap (minted to the
//   publisher at publish-time `init`), so only the deployer can call this, once.
//   Sender becomes operator + gets AdminCap; `relayer` address receives the RelayerCap.
export interface InitializeArgs {
  packageId: string;
  bootstrapCapId: string;
  relayer: string;
  relayerEncryptionKey: Uint8Array | number[];
  escalateThreshold: number;
  blockThreshold: number;
  maxStrikes: number;
  emaAlpha: number;
  emaScale: number;
}

export function initialize(tx: Transaction, args: InitializeArgs) {
  if (args.relayerEncryptionKey.length !== 32) {
    throw new Error(
      `relayerEncryptionKey must be 32 bytes (x25519), got ${args.relayerEncryptionKey.length}`
    );
  }
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.initialize}::${MODULES.initialize}`,
    arguments: [
      tx.object(args.bootstrapCapId),
      tx.pure.address(args.relayer),
      tx.pure.vector("u8", Array.from(args.relayerEncryptionKey)),
      tx.pure.u32(args.escalateThreshold),
      tx.pure.u32(args.blockThreshold),
      tx.pure.u8(args.maxStrikes),
      tx.pure.u16(args.emaAlpha),
      tx.pure.u16(args.emaScale),
    ],
  });
}
