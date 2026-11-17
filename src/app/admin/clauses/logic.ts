// Pure logic behind the clause actions; deps are injected so it can be tested without Next or Supabase.
import { CLAUSE_KEYS } from "@/documents/clauseKeys";
import { sampleClauseVars } from "@/documents/clauseSample";
import { renderClause, UnknownClauseVariable } from "@/documents/clauses";
import type { SessionContext } from "@/lib/session";
import { isAdminCtx, NOT_ADMIN, type AdminResult } from "../common";

export interface ClauseDeps {
  /** Highest existing version of a key, or null if none. */
  latest(key: string): Promise<{ version: number; body: string } | null>;
  /** Inserts one row. "conflict" means (key, version) already exists (a concurrent save won). Never updates. */
  insert(row: { key: string; version: number; body: string; createdBy: string }): Promise<"ok" | "conflict">;
}

const MAX_ATTEMPTS = 3;
const MAX_BODY = 50_000;

export async function saveClause(ctx: SessionContext, key: unknown, body: unknown, d: ClauseDeps): Promise<AdminResult> {
  if (!isAdminCtx(ctx)) return NOT_ADMIN;
  if (typeof key !== "string" || !(CLAUSE_KEYS as readonly string[]).includes(key)) {
    return { ok: false, message: "Unknown clause." };
  }
  if (typeof body !== "string" || body.trim() === "") return { ok: false, message: "Clause text is required." };
  if (body.length > MAX_BODY) return { ok: false, message: `Clause text must be at most ${MAX_BODY} characters.` };

  try {
    renderClause(body, sampleClauseVars());
  } catch (e) {
    if (e instanceof UnknownClauseVariable) {
      return { ok: false, message: `Unknown variable {{${e.variable}}}. Use only the variables listed on this page.` };
    }
    throw e;
  }

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const current = await d.latest(key);
    if (current && current.body === body) {
      return { ok: false, message: "The text is the same as the current version; nothing was saved." };
    }
    const version = (current?.version ?? 0) + 1;
    const res = await d.insert({ key, version, body, createdBy: ctx.userId });
    if (res === "ok") return { ok: true, message: `Saved as version ${version}.` };
    // Someone else saved this key between our read and write: re-read and try the next version.
  }
  return { ok: false, message: "Another administrator saved this clause at the same moment. Reload the page and try again." };
}
