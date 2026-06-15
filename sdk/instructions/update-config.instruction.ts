import { Transaction } from "@mysten/sui/transactions";
import { bcs } from "@mysten/sui/bcs";
import { MODULES } from "../common/constants";

// pkg::update_config::update_config(AdminCap, &mut Config, Option<...> x7).
// Each field left undefined is sent as Option::none and stays unchanged.
export interface UpdateConfigArgs {
  packageId: string;
  configId: string;
  adminCapId: string;
  relayer?: string;
  relayerEncryptionKey?: Uint8Array | number[];
  escalateThreshold?: number;
  blockThreshold?: number;
  maxStrikes?: number;
  emaAlpha?: number;
  emaScale?: number;
}

export function updateConfig(tx: Transaction, args: UpdateConfigArgs) {
  if (args.relayerEncryptionKey !== undefined && args.relayerEncryptionKey.length !== 32) {
    throw new Error(
      `relayerEncryptionKey must be 32 bytes (x25519), got ${args.relayerEncryptionKey.length}`
    );
  }
  const optAddr = (v?: string) =>
    tx.pure(bcs.option(bcs.Address).serialize(v ?? null));
  const optVecU8 = (v?: Uint8Array | number[]) =>
    tx.pure(bcs.option(bcs.vector(bcs.u8())).serialize(v ? Array.from(v) : null));
  const optU = (
    t: ReturnType<typeof bcs.u32> | ReturnType<typeof bcs.u8> | ReturnType<typeof bcs.u16>,
    v?: number
  ) => tx.pure(bcs.option(t).serialize(v ?? null));

  return tx.moveCall({
    target: `${args.packageId}::${MODULES.updateConfig}::${MODULES.updateConfig}`,
    arguments: [
      tx.object(args.adminCapId),
      tx.object(args.configId),
      optAddr(args.relayer),
      optVecU8(args.relayerEncryptionKey),
      optU(bcs.u32(), args.escalateThreshold),
      optU(bcs.u32(), args.blockThreshold),
      optU(bcs.u8(), args.maxStrikes),
      optU(bcs.u16(), args.emaAlpha),
      optU(bcs.u16(), args.emaScale),
    ],
  });
}
