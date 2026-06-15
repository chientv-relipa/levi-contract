import type { SuiClient, SuiTransactionBlockResponse } from "@mysten/sui/client";
import type { Signer } from "@mysten/sui/cryptography";
import { Transaction } from "@mysten/sui/transactions";
import { blake3 } from "@noble/hashes/blake3";

import type { LeviAddresses } from "../common/constants";
import { MAX_PAYLOAD } from "../common/constants";
import type { AllowedTarget } from "../types";
import {
  encodeActionPayload,
  encryptForRelayer,
  commitmentHashAsArray,
} from "../crypto";
import * as ix from "../instructions";
import {
  getConfig,
  getAgent,
  getAction,
  getAgentIdFromRegistry,
  findCreatedObjectId,
  parseAllowedTargets,
} from "./objects";

export interface LeviClientOpts {
  adminCapId?: string;
  relayerCapId?: string;
}

const EXEC_OPTS = {
  showEffects: true,
  showObjectChanges: true,
  showEvents: true,
} as const;

/**
 * Ergonomic wrapper: builds the PTB, signs, executes, waits, and returns the
 * created object IDs / parsed state. Thin layer over the `instructions/` builders.
 */
export class LeviClient {
  constructor(
    public readonly client: SuiClient,
    public readonly addresses: LeviAddresses,
    public readonly opts: LeviClientOpts = {}
  ) {}

  // ----- reads -----
  getConfig() {
    return getConfig(this.client, this.addresses.configId);
  }
  getAgent(agentId: string) {
    return getAgent(this.client, agentId);
  }
  getAction(actionObjectId: string) {
    return getAction(this.client, actionObjectId);
  }
  async getAllowedTargets(agentId: string): Promise<AllowedTarget[]> {
    const res = await this.client.getObject({ id: agentId, options: { showContent: true } });
    return parseAllowedTargets((res.data?.content as any)?.fields);
  }
  getAgentId(agentWallet: string) {
    return getAgentIdFromRegistry(this.client, this.addresses.registryId, agentWallet);
  }

  /** Next monotonic action_id for an agent (its `action_counter` + 1). */
  async nextActionId(agentId: string): Promise<bigint> {
    const agent = await this.getAgent(agentId);
    return agent.actionCounter + 1n;
  }

  private async run(tx: Transaction, signer: Signer): Promise<SuiTransactionBlockResponse> {
    const res = await this.client.signAndExecuteTransaction({
      transaction: tx,
      signer,
      options: EXEC_OPTS,
    });
    await this.client.waitForTransaction({ digest: res.digest });
    return res;
  }

  // ----- agent lifecycle -----
  async registerAgent(
    owner: Signer,
    params: { agentWallet: string; spendLimit: bigint | number }
  ): Promise<{ response: SuiTransactionBlockResponse; agentId: string }> {
    const tx = new Transaction();
    ix.registerAgent(tx, {
      packageId: this.addresses.packageId,
      configId: this.addresses.configId,
      registryId: this.addresses.registryId,
      agentWallet: params.agentWallet,
      spendLimit: params.spendLimit,
    });
    const response = await this.run(tx, owner);
    const agentId = findCreatedObjectId(response, "::agent::Agent");
    if (!agentId) throw new Error("register_agent: Agent object not found in tx effects");
    return { response, agentId };
  }

  async activateAgent(owner: Signer, agentId: string) {
    const tx = new Transaction();
    ix.activateAgent(tx, { packageId: this.addresses.packageId, configId: this.addresses.configId, agentId });
    return this.run(tx, owner);
  }

  async deactivateAgent(owner: Signer, agentId: string) {
    const tx = new Transaction();
    ix.deactivateAgent(tx, { packageId: this.addresses.packageId, configId: this.addresses.configId, agentId });
    return this.run(tx, owner);
  }

  async updateAgentProgramTarget(
    owner: Signer,
    params: { agentId: string; target: string; allowed: boolean }
  ) {
    const tx = new Transaction();
    ix.updateAgentProgramTarget(tx, {
      packageId: this.addresses.packageId,
      configId: this.addresses.configId,
      ...params,
    });
    return this.run(tx, owner);
  }

  // ----- admin -----
  async updateConfig(
    admin: Signer,
    params: Omit<ix.UpdateConfigArgs, "packageId" | "configId" | "adminCapId">
  ) {
    if (!this.opts.adminCapId) throw new Error("adminCapId required for updateConfig");
    const tx = new Transaction();
    ix.updateConfig(tx, {
      packageId: this.addresses.packageId,
      configId: this.addresses.configId,
      adminCapId: this.opts.adminCapId,
      ...params,
    });
    return this.run(tx, admin);
  }

  async updateMaintenance(admin: Signer, on: boolean) {
    if (!this.opts.adminCapId) throw new Error("adminCapId required for updateMaintenance");
    const tx = new Transaction();
    ix.updateMaintenance(tx, {
      packageId: this.addresses.packageId,
      configId: this.addresses.configId,
      adminCapId: this.opts.adminCapId,
      on,
    });
    return this.run(tx, admin);
  }

  // ----- action flow -----
  /**
   * `protect`: encrypt {prompt, txBytes} to the relayer key, then submit_action.
   * Sender (`agentSigner`) MUST be the agent wallet. Returns the created Action ID.
   */
  async submitAction(
    agentSigner: Signer,
    params: {
      agentId: string;
      targetProgram: string;
      value: bigint | number;
      /** Omit to auto-assign the agent's next monotonic action_id. */
      actionId?: bigint | number;
      prompt: string;
      txBytes: Uint8Array;
    }
  ): Promise<{
    response: SuiTransactionBlockResponse;
    actionObjectId: string;
    actionId: bigint | number;
  }> {
    const config = await this.getConfig();
    const plaintext = encodeActionPayload({ prompt: params.prompt, tx: params.txBytes });
    const { payload } = encryptForRelayer({
      plaintext,
      relayerPublicKey: config.relayerEncryptionKey,
    });
    if (payload.length > MAX_PAYLOAD) {
      throw new Error(
        `encrypted payload is ${payload.length} bytes, exceeds MAX_PAYLOAD (${MAX_PAYLOAD})`
      );
    }
    const commitment = commitmentHashAsArray(plaintext);
    const actionId = params.actionId ?? (await this.nextActionId(params.agentId));

    const tx = new Transaction();
    ix.submitAction(tx, {
      packageId: this.addresses.packageId,
      configId: this.addresses.configId,
      agentId: params.agentId,
      targetProgram: params.targetProgram,
      value: params.value,
      actionId,
      encryptedPayload: payload,
      commitmentHash: commitment,
    });
    const response = await this.run(tx, agentSigner);
    const actionObjectId = findCreatedObjectId(response, "::action::Action");
    if (!actionObjectId) throw new Error("submit_action: Action object not found in tx effects");
    return { response, actionObjectId, actionId };
  }

  async verdict(
    relayer: Signer,
    params: { agentId: string; actionObjectId: string; rawScore: number; reasoning: string }
  ) {
    if (!this.opts.relayerCapId) throw new Error("relayerCapId required for verdict");
    const tx = new Transaction();
    ix.verdictAction(tx, {
      packageId: this.addresses.packageId,
      configId: this.addresses.configId,
      relayerCapId: this.opts.relayerCapId,
      agentId: params.agentId,
      actionId: params.actionObjectId,
      rawScore: params.rawScore,
      reasoningHash: Array.from(blake3(new TextEncoder().encode(params.reasoning))),
    });
    return this.run(tx, relayer);
  }

  async approve(owner: Signer, params: { agentId: string; actionObjectId: string }) {
    const tx = new Transaction();
    ix.approveAction(tx, {
      packageId: this.addresses.packageId,
      agentId: params.agentId,
      actionId: params.actionObjectId,
    });
    return this.run(tx, owner);
  }

  async reject(owner: Signer, params: { agentId: string; actionObjectId: string }) {
    const tx = new Transaction();
    ix.rejectAction(tx, {
      packageId: this.addresses.packageId,
      configId: this.addresses.configId,
      agentId: params.agentId,
      actionId: params.actionObjectId,
    });
    return this.run(tx, owner);
  }
}
