// Seeding step, not a test: renders the published PDFs (RFB, bid form and, for an addendum version, the addendum) of
// every seeded solicitation version and uploads them to the paths supabase/seed.sql gives them, so the seeded download
// links open real documents. It uses the app's own renderers and the same context publishing builds.
//
// Run with `npm run seed:docs` (local stack, after `npm run db:reset`); `npm run hosted:reset` runs it with
// SEED_TARGET=hosted against HOSTED_SUPABASE_URL and HOSTED_SERVICE_ROLE_KEY. It uses the service key, so it is a
// script, never app code.
import { execSync } from "node:child_process";
import { createClient } from "@supabase/supabase-js";
import { expect, it } from "vitest";
import { dateChanges, type AddendumDocContext } from "@/documents/addendumDoc";
import type { DocContext } from "@/documents/clauses";
import { chromiumRenderer, renderPdf } from "@/documents/pdf";
import { renderAddendumHtml, renderBidFormHtml, renderRfbHtml } from "@/documents/renderHtml";
import { diffSchedule } from "@/domain/addendum/diff";
import { emptySolicitation, solicitationSchema } from "@/domain/solicitation/schema";
import { todayIn } from "@/domain/time";

function target(): { url: string; key: string } {
  if (process.env.SEED_TARGET === "hosted") {
    const url = process.env.HOSTED_SUPABASE_URL;
    const key = process.env.HOSTED_SERVICE_ROLE_KEY;
    if (!url || !key) throw new Error("SEED_TARGET=hosted needs HOSTED_SUPABASE_URL and HOSTED_SERVICE_ROLE_KEY.");
    return { url, key };
  }
  const out = execSync("npx supabase status -o env", { encoding: "utf8" });
  const env = Object.fromEntries(out.split(/\r?\n/).filter((l) => l.includes("="))
    .map((l) => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^"|"$/g, "")]; }));
  const host = new URL(env.API_URL).hostname;
  if (host !== "127.0.0.1" && host !== "localhost") throw new Error(`Refusing to run against ${host}: local only.`);
  return { url: env.API_URL, key: env.SERVICE_ROLE_KEY };
}

interface Snapshot { data?: object; clauses?: Record<string, string>; settings?: DocContext["settings"] }

interface VersionRow {
  solicitation_id: string; version: number; snapshot: Snapshot | null; rfb_path: string; bid_form_path: string;
  addendum_path: string | null; published_at: string; number: string; agency_name: string; timezone: string;
  addendum_number: number | null; addendum_narrative: string | null;
  answers: { publishedQuestion: string; answer: string }[];
}

/** The seeded versions, read as the database owner (the API roles have no grant on solicitation_versions). */
function versionRows(): VersionRow[] {
  const remote = process.env.SEED_TARGET === "hosted" ? " --remote" : "";
  const out = execSync(`npx supabase db query --read-only --output-format json -f scripts/seed-documents.sql${remote}`,
                       { encoding: "utf8", stdio: ["ignore", "pipe", "inherit"] });
  const rows = (JSON.parse(out) as { rows?: VersionRow[] }).rows;
  if (!rows) throw new Error("supabase db query returned no rows field.");
  // jsonb columns may come back as text.
  return rows.map((r) => ({
    ...r,
    version: Number(r.version),
    addendum_number: r.addendum_number === null ? null : Number(r.addendum_number),
    snapshot: typeof r.snapshot === "string" ? JSON.parse(r.snapshot) : r.snapshot,
    answers: typeof r.answers === "string" ? JSON.parse(r.answers) : r.answers,
  }));
}

it("renders and uploads every seeded version's published documents", async () => {
  const { url, key } = target();
  const published = createClient(url, key, { auth: { persistSession: false } }).storage.from("published");
  const put = async (path: string, bytes: Uint8Array) => {
    const { error } = await published.upload(path, bytes, { upsert: true, contentType: "application/pdf" });
    if (error) throw new Error(`${path}: ${error.message}`);
  };
  const renderer = chromiumRenderer();

  const contexts = new Map<string, DocContext>();
  let uploaded = 0;
  for (const v of versionRows()) {
    const snap = v.snapshot;
    if (!snap?.data || !snap.clauses || !snap.settings) throw new Error(`Bad seeded version ${v.number} v${v.version}`);
    const ctx: DocContext = {
      data: solicitationSchema.parse({ ...emptySolicitation(), ...snap.data }),
      number: v.number,
      version: v.version,
      settings: snap.settings,
      agencyName: v.agency_name,
      clauses: snap.clauses,
    };
    contexts.set(`${v.solicitation_id}/${v.version}`, ctx);

    await put(v.rfb_path, await renderPdf(renderRfbHtml(ctx, { draft: false }), renderer));
    await put(v.bid_form_path, await renderPdf(renderBidFormHtml(ctx, { draft: false }), renderer));
    uploaded += 2;

    if (v.addendum_path) {
      const prev = contexts.get(`${v.solicitation_id}/${v.version - 1}`);
      if (!prev || v.addendum_number === null) throw new Error(`${v.number} v${v.version}: no prior version or addendum`);
      const addendumCtx: AddendumDocContext = {
        number: v.addendum_number,
        version: v.version,
        solicitationNumber: v.number,
        title: ctx.data.longTitle,
        publishedOn: todayIn(v.timezone, new Date(v.published_at)),
        narrative: v.addendum_narrative ?? "",
        changes: diffSchedule(prev.data.schedule, ctx.data.schedule),
        dateChanges: dateChanges(prev.data, ctx.data, v.timezone),
        answers: v.answers,
      };
      await put(v.addendum_path, await renderPdf(renderAddendumHtml(addendumCtx), renderer));
      uploaded++;
    }
  }
  console.log(`Uploaded ${uploaded} published documents.`);
  expect(uploaded).toBeGreaterThan(0);
}, 10 * 60_000);
