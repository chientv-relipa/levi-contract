import assert from "node:assert";
import "dotenv/config";
import { describe, it, beforeAll } from "vitest";

import { SuiClient, getFullnodeUrl } from "@mysten/sui/client";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { decodeSuiPrivateKey } from "@mysten/sui/cryptography";
import { normalizeSuiAddress } from "@mysten/sui/utils";

import {
  LeviClient,
  TESTNET_ADDRESSES,
  testnetLeviAddresses,
  actionStatus,
  generateX25519Keypair,
  type LeviAddresses,
} from "../sdk";

// End-to-end tests against the live testnet deployment. Requires OPERATOR_SECRET_KEY
// in .env (the operator wallet holding AdminCap + RelayerCap, with some testnet SUI).
//
// Flow mirrors the Solana Bento suite: register agent -> submit -> verdict
// (approve / escalate) -> owner approve / reject.

const RPC = process.env.SUI_RPC_URL ?? getFullnodeUrl("testnet");
const TARGET = normalizeSuiAddress("0xdead"); // stand-in target program

const addresses: LeviAddresses = {
  packageId: process.env.LEVI_PACKAGE_ID ?? testnetLeviAddresses().packageId,
  configId: process.env.LEVI_CONFIG_ID ?? testnetLeviAddresses().configId,
  registryId: process.env.LEVI_REGISTRY_ID ?? testnetLeviAddresses().registryId,
};
const adminCapId = process.env.LEVI_ADMIN_CAP_ID ?? TESTNET_ADDRESSES.adminCapId;
const relayerCapId = process.env.LEVI_RELAYER_CAP_ID ?? TESTNET_ADDRESSES.relayerCapId;

const hasKey = !!process.env.OPERATOR_SECRET_KEY;

(hasKey ? describe : describe.skip)("Levi e2e (testnet)", function () {
  const client = new SuiClient({ url: RPC });
  let operator: Ed25519Keypair;
  let levi: LeviClient;
  let agent: Ed25519Keypair;
  let agentAddress: string;
  let agentId: string;
  let agent2: Ed25519Keypair;
  let agent2Id: string;

  beforeAll(async function () {
    const { secretKey } = decodeSuiPrivateKey(process.env.OPERATOR_SECRET_KEY!);
    operator = Ed25519Keypair.fromSecretKey(secretKey);
    levi = new LeviClient(client, addresses, { adminCapId, relayerCapId });

    // 1) Set a real x25519 relayer encryption key so encryptForRelayer works.
    const relayerEnc = generateX25519Keypair();
    await levi.updateConfig(operator, { relayerEncryptionKey: relayerEnc.publicKey });

    // 2) Fresh agent wallet, funded from the operator so it can pay gas for submit.
    agent = Ed25519Keypair.generate();
    agentAddress = agent.getPublicKey().toSuiAddress();
    const fund = new Transaction();
    const [coin] = fund.splitCoins(fund.gas, [100_000_000]); // 0.1 SUI
    fund.transferObjects([coin], agentAddress);
    const f = await client.signAndExecuteTransaction({ transaction: fund, signer: operator });
    await client.waitForTransaction({ digest: f.digest });
  });

  it("registers an agent", async function () {
    const res = await levi.registerAgent(operator, {
      agentWallet: agentAddress,
      spendLimit: 1_000_000n,
    });
    agentId = res.agentId;
    const a = await levi.getAgent(agentId);
    assert.strictEqual(a.agentWallet, agentAddress);
    assert.strictEqual(a.owner, operator.getPublicKey().toSuiAddress());
    assert.strictEqual(a.active, true);
    assert.strictEqual(a.threatScore, 0);
    assert.strictEqual(a.strikes, 0);
  });

  it("submit -> verdict APPROVES a low-score action", async function () {
    const { actionObjectId } = await levi.submitAction(agent, {
      agentId,
      targetProgram: TARGET,
      value: 1_000n,
      actionId: 1n,
      prompt: "swap 50 USDC to SOL on cetus",
      txBytes: new TextEncoder().encode("dummy-ptb-bytes"),
    });

    await levi.verdict(operator, {
      agentId,
      actionObjectId,
      rawScore: 5_000,
      reasoning: "looks safe: known target, within spend limit",
    });

    const action = await levi.getAction(actionObjectId);
    assert.strictEqual(action.status, actionStatus.approved);
    assert.strictEqual(action.decision, actionStatus.approved);
    assert.strictEqual(action.rawScore, 5_000);

    const a = await levi.getAgent(agentId);
    assert.strictEqual(a.totalApproved, 1n);
    assert.strictEqual(a.threatScore, 1_500); // EMA: 300*5000/1000
    assert.strictEqual(a.strikes, 0);
  });

  it("submit -> verdict ESCALATES, owner APPROVES", async function () {
    const { actionObjectId } = await levi.submitAction(agent, {
      agentId,
      targetProgram: TARGET,
      value: 5_000n,
      actionId: 2n,
      prompt: "swap 80 USDC into a brand-new token",
      txBytes: new TextEncoder().encode("dummy-ptb-bytes-2"),
    });

    await levi.verdict(operator, {
      agentId,
      actionObjectId,
      rawScore: 50_000,
      reasoning: "uncertain: unverified token",
    });
    let action = await levi.getAction(actionObjectId);
    assert.strictEqual(action.status, actionStatus.escalated);

    await levi.approve(operator, { agentId, actionObjectId });
    action = await levi.getAction(actionObjectId);
    assert.strictEqual(action.status, actionStatus.approved);
    // decision stays frozen at the verdict value (escalated)
    assert.strictEqual(action.decision, actionStatus.escalated);

    const a = await levi.getAgent(agentId);
    assert.strictEqual(a.totalEscalated, 1n);
    assert.strictEqual(a.strikes, 0); // approve adds no strike
  });

  it("submit -> verdict ESCALATES, owner REJECTS (adds a strike)", async function () {
    const before = await levi.getAgent(agentId);

    const { actionObjectId } = await levi.submitAction(agent, {
      agentId,
      targetProgram: TARGET,
      value: 9_000n,
      actionId: 3n,
      prompt: "swap into another unverified token",
      txBytes: new TextEncoder().encode("dummy-ptb-bytes-3"),
    });

    await levi.verdict(operator, {
      agentId,
      actionObjectId,
      rawScore: 55_000,
      reasoning: "uncertain again",
    });
    await levi.reject(operator, { agentId, actionObjectId });

    const action = await levi.getAction(actionObjectId);
    assert.strictEqual(action.status, actionStatus.rejected);

    const a = await levi.getAgent(agentId);
    assert.strictEqual(a.strikes, before.strikes + 1); // reject adds a strike
  });

  it("blocked verdicts add strikes and auto-deactivate at max_strikes", async function () {
    // Fresh agent so the strike count is clean and independent of earlier tests.
    // Kept at describe scope so later lifecycle tests can reuse it.
    agent2 = Ed25519Keypair.generate();
    const a2Addr = agent2.getPublicKey().toSuiAddress();
    const fund = new Transaction();
    const [coin] = fund.splitCoins(fund.gas, [200_000_000]); // 0.2 SUI for the loop
    fund.transferObjects([coin], a2Addr);
    const f = await client.signAndExecuteTransaction({ transaction: fund, signer: operator });
    await client.waitForTransaction({ digest: f.digest });

    const reg = await levi.registerAgent(operator, {
      agentWallet: a2Addr,
      spendLimit: 1_000_000n,
    });
    agent2Id = reg.agentId;

    const max = (await levi.getConfig()).maxStrikes;
    let firstStatus = -1;

    for (let i = 0; i < max; i++) {
      // actionId auto-assigned (agent.action_counter + 1)
      const { actionObjectId } = await levi.submitAction(agent2, {
        agentId: agent2Id,
        targetProgram: TARGET,
        value: 1n,
        prompt: `malicious tx ${i}`,
        txBytes: new TextEncoder().encode(`bad-ptb-${i}`),
      });
      await levi.verdict(operator, {
        agentId: agent2Id,
        actionObjectId,
        rawScore: 80_000, // >= block_threshold
        reasoning: "blocked: known scam target",
      });
      if (i === 0) firstStatus = (await levi.getAction(actionObjectId)).status;
    }

    assert.strictEqual(firstStatus, actionStatus.blocked);
    const a = await levi.getAgent(agent2Id);
    assert.strictEqual(a.totalBlocked, BigInt(max));
    assert.strictEqual(a.strikes, max);
    assert.strictEqual(a.active, false); // auto-deactivated once strikes hit max
  });

  it("owner reactivates then deactivates an agent", async function () {
    // agent2 was auto-deactivated above — reactivate it, then deactivate again.
    await levi.activateAgent(operator, agent2Id);
    let a = await levi.getAgent(agent2Id);
    assert.strictEqual(a.active, true);

    await levi.deactivateAgent(operator, agent2Id);
    a = await levi.getAgent(agent2Id);
    assert.strictEqual(a.active, false);
  });

  it("owner adds and toggles an allowed-target whitelist entry", async function () {
    const target = normalizeSuiAddress("0xbeef");

    await levi.updateAgentProgramTarget(operator, { agentId, target, allowed: true });
    let targets = await levi.getAllowedTargets(agentId);
    let entry = targets.find((t) => t.target === target);
    assert.ok(entry, "target should be present after add");
    assert.strictEqual(entry!.allowed, true);

    // toggling an existing target updates in place (no duplicate entry)
    await levi.updateAgentProgramTarget(operator, { agentId, target, allowed: false });
    targets = await levi.getAllowedTargets(agentId);
    const matches = targets.filter((t) => t.target === target);
    assert.strictEqual(matches.length, 1, "no duplicate entry");
    assert.strictEqual(matches[0].allowed, false);
  });

  it("admin toggles maintenance, which blocks mutating handlers", async function () {
    await levi.updateMaintenance(operator, true);
    assert.strictEqual((await levi.getConfig()).maintenance, true);

    // while in maintenance, a mutating handler must abort
    await assert.rejects(levi.deactivateAgent(operator, agentId));

    // restore so we never leave the shared Config in maintenance
    await levi.updateMaintenance(operator, false);
    assert.strictEqual((await levi.getConfig()).maintenance, false);
  });
});
