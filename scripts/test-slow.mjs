// Runs only the [slow] tests and fails (instead of skipping) when Chromium is missing.
import { spawnSync } from "node:child_process";

const r = spawnSync("npx", ["vitest", "run", "-t", "slow", ...process.argv.slice(2)], {
  stdio: "inherit",
  shell: true,
  env: { ...process.env, REQUIRE_CHROMIUM: "1" },
});
process.exit(r.status ?? 1);
