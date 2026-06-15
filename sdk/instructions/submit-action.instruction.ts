import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::submit_action::submit_action(&Config, &mut Agent, target_program, value,
//   action_id, encrypted_payload, commitment_hash). Sender MUST be the agent wallet.
// Creates + shares a new Action object in PENDING.
export interface SubmitActionArgs {
  packageId: string;
  configId: string;
  agentId: string;
  targetProgram: string;
  value: bigint | number;
  actionId: bigint | number;
  encryptedPayload: Uint8Array | number[];
  commitmentHash: Uint8Array | number[];
}

export function submitAction(tx: Transaction, args: SubmitActionArgs) {
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.submitAction}::${MODULES.submitAction}`,
    arguments: [
      tx.object(args.configId),
      tx.object(args.agentId),
      tx.pure.address(args.targetProgram),
      tx.pure.u64(args.value),
      tx.pure.u64(args.actionId),
      tx.pure.vector("u8", Array.from(args.encryptedPayload)),
      tx.pure.vector("u8", Array.from(args.commitmentHash)),
    ],
  });
}
