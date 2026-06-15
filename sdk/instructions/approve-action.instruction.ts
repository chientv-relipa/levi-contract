import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::approve_action::approve_action(&Agent, &mut Action). Sender = agent owner.
// Escalated -> Approved (no strike).
export interface ApproveActionArgs {
  packageId: string;
  agentId: string;
  actionId: string;
}

export function approveAction(tx: Transaction, args: ApproveActionArgs) {
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.approveAction}::${MODULES.approveAction}`,
    arguments: [tx.object(args.agentId), tx.object(args.actionId)],
  });
}
