import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::register_agent::register_agent(&mut Config, &mut AgentRegistry, agent_wallet, spend_limit)
// Sender = owner. Creates + shares a new Agent object.
export interface RegisterAgentArgs {
  packageId: string;
  configId: string;
  registryId: string;
  agentWallet: string;
  spendLimit: bigint | number;
}

export function registerAgent(tx: Transaction, args: RegisterAgentArgs) {
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.registerAgent}::${MODULES.registerAgent}`,
    arguments: [
      tx.object(args.configId),
      tx.object(args.registryId),
      tx.pure.address(args.agentWallet),
      tx.pure.u64(args.spendLimit),
    ],
  });
}
