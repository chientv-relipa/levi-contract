import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::deactivate_agent::deactivate_agent(&Config, &mut Agent). Sender = owner.
export interface DeactivateAgentArgs {
  packageId: string;
  configId: string;
  agentId: string;
}

export function deactivateAgent(tx: Transaction, args: DeactivateAgentArgs) {
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.deactivateAgent}::${MODULES.deactivateAgent}`,
    arguments: [tx.object(args.configId), tx.object(args.agentId)],
  });
}
