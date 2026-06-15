import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::update_agent_program_target::update_agent_program_target(&Config, &mut Agent, target, allowed)
// Sender = owner. Adds a new whitelist entry or toggles an existing target's flag.
export interface UpdateAgentProgramTargetArgs {
  packageId: string;
  configId: string;
  agentId: string;
  target: string;
  allowed: boolean;
}

export function updateAgentProgramTarget(
  tx: Transaction,
  args: UpdateAgentProgramTargetArgs
) {
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.updateAgentProgramTarget}::${MODULES.updateAgentProgramTarget}`,
    arguments: [
      tx.object(args.configId),
      tx.object(args.agentId),
      tx.pure.address(args.target),
      tx.pure.bool(args.allowed),
    ],
  });
}
