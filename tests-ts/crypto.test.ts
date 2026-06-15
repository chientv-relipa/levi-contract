import assert from "node:assert";
import { describe, it } from "vitest";

import {
  generateX25519Keypair,
  encryptForRelayer,
  decryptFromAgent,
  commitmentHash,
  encodeActionPayload,
  decodeActionPayload,
  NONCE_LENGTH,
  X25519_KEY_LENGTH,
} from "../sdk";

// Offline unit tests for the relayer-shared crypto layer. No network / key needed,
// so these always run. They prove the SDK encrypt/commit path matches what the
// relayer's decrypt/verify path will recompute.

describe("crypto layer (offline)", () => {
  it("encrypt -> decrypt recovers the plaintext", () => {
    const relayer = generateX25519Keypair();
    const plaintext = new TextEncoder().encode("swap 50 USDC to SOL on cetus");
    const { payload } = encryptForRelayer({
      plaintext,
      relayerPublicKey: relayer.publicKey,
    });
    const { plaintext: out } = decryptFromAgent({
      payload,
      relayerSecretKey: relayer.secretKey,
    });
    assert.deepStrictEqual(Array.from(out), Array.from(plaintext));
  });

  it("envelope is ephemeralPub(32) || nonce(12) || ciphertext", () => {
    const relayer = generateX25519Keypair();
    const plaintext = new Uint8Array([1, 2, 3, 4]);
    const { payload, ciphertext } = encryptForRelayer({
      plaintext,
      relayerPublicKey: relayer.publicKey,
    });
    assert.strictEqual(
      payload.length,
      X25519_KEY_LENGTH + NONCE_LENGTH + ciphertext.length
    );
  });

  it("commitment is deterministic and 32 bytes", () => {
    const p = new TextEncoder().encode("abc");
    const h1 = commitmentHash(p);
    const h2 = commitmentHash(p);
    assert.strictEqual(h1.length, 32);
    assert.deepStrictEqual(Array.from(h1), Array.from(h2));
  });

  it("action payload encode -> decode round-trips (prompt + tx)", () => {
    const tx = new Uint8Array([9, 8, 7, 6, 5, 0, 255]);
    const enc = encodeActionPayload({ prompt: "swap 50 USDC", tx });
    const dec = decodeActionPayload(enc);
    assert.strictEqual(dec.prompt, "swap 50 USDC");
    assert.deepStrictEqual(Array.from(dec.tx), Array.from(tx));
  });

  it("relayer recomputes the same commitment after decrypt", () => {
    const relayer = generateX25519Keypair();
    const plaintext = encodeActionPayload({
      prompt: "swap",
      tx: new Uint8Array([42, 42]),
    });
    const commitment = commitmentHash(plaintext); // SDK computes before encryption
    const { payload } = encryptForRelayer({
      plaintext,
      relayerPublicKey: relayer.publicKey,
    });
    const { plaintext: recovered } = decryptFromAgent({
      payload,
      relayerSecretKey: relayer.secretKey,
    });
    // relayer recomputes over the decrypted bytes — must match the on-chain commitment
    assert.deepStrictEqual(
      Array.from(commitmentHash(recovered)),
      Array.from(commitment)
    );
  });

  it("decrypt with the wrong relayer key fails (tamper/eavesdrop protection)", () => {
    const relayer = generateX25519Keypair();
    const attacker = generateX25519Keypair();
    const { payload } = encryptForRelayer({
      plaintext: new Uint8Array([1, 2, 3]),
      relayerPublicKey: relayer.publicKey,
    });
    assert.throws(() =>
      decryptFromAgent({ payload, relayerSecretKey: attacker.secretKey })
    );
  });
});
