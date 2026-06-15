import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::reject_action::reject_action(&Config, &mut Agent, &mut Action). Sender = owner.
// Escalated -> Rejected, adds a strike (may auto-deactivate the agent).
export interface RejectActionArgs {
  packageId: string;
  configId: string;
  agentId: string;
  actionId: string;
}

export function rejectAction(tx: Transaction, args: RejectActionArgs) {
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.rejectAction}::${MODULES.rejectAction}`,
    arguments: [
      tx.object(args.configId),
      tx.object(args.agentId),
      tx.object(args.actionId),
    ],
  });
}
