// The live AI check evaluation (npm run aicheck:eval). Separate from vitest.config.ts so `npm test` never runs it.
import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

export default defineConfig({
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
      // server-only throws outside a React server build; the eval is a trusted local script.
      "server-only": fileURLToPath(new URL("./scripts/empty.mjs", import.meta.url)),
    },
  },
  test: {
    environment: "node",
    include: ["scripts/aicheck-eval.live.test.ts"],
    testTimeout: 30 * 60_000,
  },
});
