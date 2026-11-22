// The published-document seeding step (npm run seed:docs). Separate from vitest.config.ts so `npm test` never runs it.
import { defineConfig } from "vitest/config";
import { fileURLToPath } from "node:url";

export default defineConfig({
  oxc: { jsx: { runtime: "automatic" } },
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
      // server-only throws outside a React server build; this is a trusted local script.
      "server-only": fileURLToPath(new URL("./scripts/empty.mjs", import.meta.url)),
    },
  },
  test: {
    environment: "node",
    include: ["scripts/seed-documents.live.test.ts"],
    testTimeout: 10 * 60_000,
  },
});
