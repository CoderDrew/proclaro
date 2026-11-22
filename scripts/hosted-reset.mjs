// Resets the hosted database to the seed: reruns every migration and supabase/seed.sql on the linked project, uploads
// the seed files and the seeded solicitations' published PDFs, then checks the demo password. Run with `npm run hosted:reset` (reads .env.hosted, never committed).
//
// supabase/seed.sql uses the public local password. This script seeds from a temporary, git-ignored copy with
// DEMO_PASSWORD in its place, so the public password never exists on the hosted database. Afterwards it signs in with
// both and fails loudly if the public one works.
import { spawnSync } from "node:child_process";
import { readFileSync, rmSync, writeFileSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { createClient } from "@supabase/supabase-js";

const PUBLIC_LOCAL_PASSWORD = "proclaro-dev";
const PROBE = "admin@example.test";
const SEED = "supabase/seed.sql";
const HOSTED_SEED = "supabase/.hosted-seed.sql";

/** The seed with every crypt('proclaro-dev', ...) using the demo password instead. Exported for the test. */
export function hostedSeed(sql, password) {
  const literal = `'${password.replace(/'/g, "''")}'`;
  const out = sql.replaceAll(`crypt('${PUBLIC_LOCAL_PASSWORD}'`, () => `crypt(${literal}`);
  if (out.includes(`'${PUBLIC_LOCAL_PASSWORD}'`)) throw new Error("The seed still contains the local password.");
  if (out === sql) throw new Error("The seed sets no passwords: has seed.sql changed?");
  return out;
}

function need(name) {
  const v = process.env[name]?.trim();
  if (!v) throw new Error(`Missing ${name} (set it in .env.hosted).`);
  return v;
}

function run(cmd, args) {
  const r = spawnSync(cmd, args, { stdio: "inherit", shell: process.platform === "win32" });
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(" ")} failed.`);
}

async function signsIn(url, anonKey, password) {
  const client = createClient(url, anonKey, { auth: { persistSession: false } });
  const { error } = await client.auth.signInWithPassword({ email: PROBE, password });
  return !error;
}

async function main() {
  const url = need("HOSTED_SUPABASE_URL");
  const anonKey = need("HOSTED_ANON_KEY");
  need("HOSTED_SERVICE_ROLE_KEY");
  const demoPassword = need("DEMO_PASSWORD");
  const host = new URL(url).hostname;
  if (host === "127.0.0.1" || host === "localhost") throw new Error("HOSTED_SUPABASE_URL points at this machine.");

  writeFileSync(HOSTED_SEED, hostedSeed(readFileSync(SEED, "utf8"), demoPassword));
  try {
    // --sql-paths is relative to the supabase directory.
    run("npx", ["supabase", "db", "reset", "--remote", "--sql-paths", ".hosted-seed.sql"]);
  } finally {
    rmSync(HOSTED_SEED, { force: true });
  }
  run("node", ["scripts/seed-files.mjs", "--hosted"]);
  // The seeded solicitations' published PDFs, rendered locally and uploaded (scripts/seed-documents.live.test.ts).
  process.env.SEED_TARGET = "hosted";
  run("npx", ["vitest", "run", "--config", "vitest.seed.config.ts"]);

  if (await signsIn(url, anonKey, PUBLIC_LOCAL_PASSWORD)) {
    throw new Error(
      `DANGER: ${PROBE} signs in with the public local password. Run this again now, or change it in the dashboard.`);
  }
  if (!(await signsIn(url, anonKey, demoPassword))) {
    throw new Error("The demo accounts don't accept DEMO_PASSWORD.");
  }
  console.log("Hosted database reset. The demo accounts accept DEMO_PASSWORD; the local password is rejected.");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { console.error(e.message ?? e); process.exit(1); });
}
