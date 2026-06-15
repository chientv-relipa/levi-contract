import { Transaction } from "@mysten/sui/transactions";
import { MODULES } from "../common/constants";

// pkg::update_maintenance::update_maintenance(AdminCap, &mut Config, on)
export interface UpdateMaintenanceArgs {
  packageId: string;
  configId: string;
  adminCapId: string;
  on: boolean;
}

export function updateMaintenance(tx: Transaction, args: UpdateMaintenanceArgs) {
  return tx.moveCall({
    target: `${args.packageId}::${MODULES.updateMaintenance}::${MODULES.updateMaintenance}`,
    arguments: [
      tx.object(args.adminCapId),
      tx.object(args.configId),
      tx.pure.bool(args.on),
    ],
  });
}
