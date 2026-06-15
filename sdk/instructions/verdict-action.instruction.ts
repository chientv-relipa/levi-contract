import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::verdict_action::verdict_action(RelayerCap, &Config, &mut Agent, &mut Action,
//   raw_score, reasoning_hash). Caller must hold the RelayerCap.
export interface VerdictActionArgs {
  packageId: string;
  configId: string;
  relayerCapId: string;
  agentId: string;
  actionId: string;
  rawScore: number;
  reasoningHash: Uint8Array | number[];
}

export function verdictAction(tx: Transaction, args: VerdictActionArgs) {
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.verdictAction}::${MODULES.verdictAction}`,
    arguments: [
      tx.object(args.relayerCapId),
      tx.object(args.configId),
      tx.object(args.agentId),
      tx.object(args.actionId),
      tx.pure.u32(args.rawScore),
      tx.pure.vector("u8", Array.from(args.reasoningHash)),
    ],
  });
}
