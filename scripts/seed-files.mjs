// Local development only: uploads the AI check fixture PDFs to the paths supabase/seed.sql gives 27-0003's bids
// (insurance certificates and scans), so the recorded check results open real documents. Run after `npm run db:reset`.
//
// It uses the LOCAL service key from `supabase status` and refuses any API URL that isn't 127.0.0.1 or localhost. It is
// a seeding script, never app code: the app never touches bid files with the service key.
import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { createClient } from "@supabase/supabase-js";

function localEnv() {
  const out = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = Object.fromEntries(out.split(/\r?\n/).filter((l) => l.includes("="))
    .map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^"|"$/g, "")]; }));
  const url = env.API_URL;
  const key = env.SERVICE_ROLE_KEY;
  if (!url || !key) throw new Error("Could not read API_URL and SERVICE_ROLE_KEY from `supabase status`.");
  const host = new URL(url).hostname;
  if (host !== "127.0.0.1" && host !== "localhost") throw new Error(`Refusing to run against ${host}: local only.`);
  return { url, key };
}

async function listAll(storage, prefix) {
  const out = [];
  const { data, error } = await storage.list(prefix, { limit: 1000 });
  if (error) throw error;
  for (const e of data ?? []) {
    const path = `${prefix}/${e.name}`;
    if (e.id === null) out.push(...(await listAll(storage, path)));
    else out.push(path);
  }
  return out;
}

/** The fixture file for a seeded path, by its file name. */
function fixtureFor(path) {
  const name = path.split("/").pop();
  let m = /^seed-([a-z]+)-insurance\.pdf$/.exec(name);
  if (m) return `${m[1]}-insurance.pdf`;
  m = /^scan-seed-([a-z]+)-(signed-form|bond)\.pdf$/.exec(name);
  if (m) return `${m[1]}-${m[2]}.pdf`;
  return null;
}

async function main() {
  const { url, key } = localEnv();
  const storage = createClient(url, key, { auth: { persistSession: false } }).storage.from("bid-files");
  const paths = (await listAll(storage, "bids")).filter((p) => fixtureFor(p));
  if (paths.length === 0) throw new Error("No seeded AI check paths found. Run `npm run db:reset` first.");
  for (const p of paths) {
    const bytes = readFileSync(join(process.cwd(), "fixtures", "aicheck", fixtureFor(p)));
    const { error } = await storage.upload(p, bytes, { upsert: true, contentType: "application/pdf" });
    if (error) throw new Error(`${p}: ${error.message}`);
  }
  console.log(`Uploaded ${paths.length} seed files.`);
}

main().catch((e) => { console.error(e.message ?? e); process.exit(1); });
