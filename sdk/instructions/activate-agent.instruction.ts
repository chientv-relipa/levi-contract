import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::activate_agent::activate_agent(&Config, &mut Agent). Sender = owner.
export interface ActivateAgentArgs {
  packageId: string;
  configId: string;
  agentId: string;
}

export function activateAgent(tx: Transaction, args: ActivateAgentArgs) {
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.activateAgent}::${MODULES.activateAgent}`,
    arguments: [tx.object(args.configId), tx.object(args.agentId)],
  });
}
