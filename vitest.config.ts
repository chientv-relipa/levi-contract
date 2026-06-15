import { defineConfig } from "vitest/config";

// E2E tests hit the live testnet (multiple sequential transactions per test), so the
// default 5s timeout is far too low. Offline unit tests are unaffected.
export default defineConfig({
  test: {
    testTimeout: 300_000, // 5 min — covers the multi-tx blocked/auto-deactivate loop
    hookTimeout: 120_000, // beforeAll: updateConfig + fund agent
  },
});
