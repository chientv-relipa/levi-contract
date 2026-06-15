import type { SuiClient, SuiTransactionBlockResponse } from "@mysten/sui/client";
import { fromBase64 } from "@mysten/sui/utils";
import type { LeviConfig, LeviAgent, LeviAction, AllowedTarget } from "../types";

// Helpers to read + parse Levi objects, and to pull created object IDs out of a tx.

/** vector<u8> fields come back from JSON-RPC as base64; normalize to bytes. */
const bytes = (v: unknown): Uint8Array =>
  typeof v === "string" ? fromBase64(v) : Uint8Array.from(v as number[]);

const fields = (obj: any): any => obj?.data?.content?.fields;

/** Find the first created object whose type ends with `suffix` (e.g. "::agent::Agent"). */
export function findCreatedObjectId(
  res: SuiTransactionBlockResponse,
  suffix: string
): string | null {
  const changes = res.objectChanges ?? [];
  for (const c of changes) {
    if (c.type === "created" && c.objectType.endsWith(suffix)) {
      return c.objectId;
    }
  }
  return null;
}

export async function getConfig(
  client: SuiClient,
  configId: string
): Promise<LeviConfig> {
  const res = await client.getObject({ id: configId, options: { showContent: true } });
  const f = fields(res);
  return {
    id: configId,
    operator: f.operator,
    relayer: f.relayer,
    relayerEncryptionKey: bytes(f.relayer_encryption_key),
    escalateThreshold: Number(f.escalate_threshold),
    blockThreshold: Number(f.block_threshold),
    maxStrikes: Number(f.max_strikes),
    emaAlpha: Number(f.ema_alpha),
    emaScale: Number(f.ema_scale),
    totalAgents: BigInt(f.total_agents),
    maintenance: Boolean(f.maintenance),
  };
}

export async function getAgent(
  client: SuiClient,
  agentId: string
): Promise<LeviAgent> {
  const res = await client.getObject({ id: agentId, options: { showContent: true } });
  const f = fields(res);
  return {
    id: agentId,
    agentWallet: f.agent_wallet,
    owner: f.owner,
    spendLimit: BigInt(f.spend_limit),
    threatScore: Number(f.threat_score),
    strikes: Number(f.strikes),
    active: Boolean(f.active),
    registeredAt: BigInt(f.registered_at),
    actionCounter: BigInt(f.action_counter),
    totalActions: BigInt(f.total_actions),
    totalApproved: BigInt(f.total_approved),
    totalBlocked: BigInt(f.total_blocked),
    totalEscalated: BigInt(f.total_escalated),
  };
}

export function parseAllowedTargets(agentContentFields: any): AllowedTarget[] {
  const arr = agentContentFields?.allowed_targets ?? [];
  return arr.map((e: any) => ({
    target: e.fields.target,
    allowed: Boolean(e.fields.allowed),
  }));
}

export async function getAction(
  client: SuiClient,
  actionId: string
): Promise<LeviAction> {
  const res = await client.getObject({ id: actionId, options: { showContent: true } });
  const f = fields(res);
  return {
    id: actionId,
    agent: f.agent,
    actionId: BigInt(f.action_id),
    targetProgram: f.target_program,
    value: BigInt(f.value),
    commitment: bytes(f.commitment),
    status: Number(f.status),
    decision: Number(f.decision),
    rawScore: Number(f.raw_score),
    reasoningHash: bytes(f.reasoning_hash),
    encryptedPayload: bytes(f.encrypted_payload),
  };
}

/**
 * Resolve an Agent object ID from a wallet address via the on-chain registry
 * (Table<address, ID>). Returns null if the wallet is not registered.
 */
export async function getAgentIdFromRegistry(
  client: SuiClient,
  registryId: string,
  agentWallet: string
): Promise<string | null> {
  const reg = await client.getObject({
    id: registryId,
    options: { showContent: true },
  });
  const tableId = fields(reg)?.agents?.fields?.id?.id;
  if (!tableId) return null;
  try {
    const field = await client.getDynamicFieldObject({
      parentId: tableId,
      name: { type: "address", value: agentWallet },
    });
    const value = (field?.data?.content as any)?.fields?.value;
    return value ?? null;
  } catch {
    return null;
  }
}
