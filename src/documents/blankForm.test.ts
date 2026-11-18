import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { blankFormResponse, type BlankFormDeps } from "./blankForm";
import { SolicitationNotFound } from "./loadDocContext";
import type { DocContext } from "./clauses";

const ID = "7d1c8a52-0000-4000-8000-000000000001";

function stub(opts: { user: boolean; visible: boolean }, calls: string[] = []): SupabaseClient<never> {
  const table = (t: string) => {
    const b: Record<string, unknown> = {};
    b.select = () => b;
    b.eq = (col: string, v: unknown) => { calls.push(`${t}.eq(${col},${String(v)})`); return b; };
    b.lte = (col: string) => { calls.push(`${t}.lte(${col})`); return b; };
    const row = t === "settings" ? { timezone: "America/Denver" } : opts.visible ? { id: ID } : null;
    b.single = () => Promise.resolve({ data: row, error: null });
    b.maybeSingle = b.single;
    return b;
  };
  return {
    auth: { getUser: () => Promise.resolve({ data: { user: opts.user ? { id: "u1" } : null } }) },
    from: table,
  } as unknown as SupabaseClient<never>;
}

const ctx = { number: "27-0001" } as unknown as DocContext;
function deps(client: SupabaseClient<never>, over: Partial<BlankFormDeps> = {}): BlankFormDeps {
  return {
    supabase: client as never, now: new Date("2026-11-18T12:00:00Z"),
    loadContext: async () => ctx, renderPdf: async () => new Uint8Array([37, 80, 68, 70]),
    ...over,
  };
}

describe("blankFormResponse", () => {
  it("401 when signed out, no-store", async () => {
    const r = await blankFormResponse(deps(stub({ user: false, visible: true })), ID);
    expect(r.status).toBe(401);
    expect(r.headers.get("Cache-Control")).toBe("private, no-store");
  });
  it("404 for a solicitation the caller cannot see, no-store", async () => {
    const r = await blankFormResponse(deps(stub({ user: true, visible: false })), ID);
    expect(r.status).toBe(404);
    expect(r.headers.get("Cache-Control")).toBe("private, no-store");
  });
  it("404 for a malformed id, no-store", async () => {
    const r = await blankFormResponse(deps(stub({ user: true, visible: true })), "nope");
    expect(r.status).toBe(404);
    expect(r.headers.get("Cache-Control")).toBe("private, no-store");
  });
  it("404 when the published snapshot is missing", async () => {
    const r = await blankFormResponse(
      deps(stub({ user: true, visible: true }), { loadContext: async () => { throw new SolicitationNotFound(ID); } }), ID);
    expect(r.status).toBe(404);
    expect(r.headers.get("Cache-Control")).toBe("private, no-store");
  });
  it("200 PDF, no-store, filtered to published and released rows", async () => {
    const calls: string[] = [];
    const r = await blankFormResponse(deps(stub({ user: true, visible: true }, calls)), ID);
    expect(r.status).toBe(200);
    expect(r.headers.get("Content-Type")).toBe("application/pdf");
    expect(r.headers.get("Cache-Control")).toBe("private, no-store");
    expect(r.headers.get("Content-Disposition")).toContain("27-0001");
    expect(calls).toContain("solicitations.eq(state,published)");
    expect(calls).toContain("solicitations.lte(release_date)");
    expect(new Uint8Array(await r.arrayBuffer()).length).toBe(4);
  });
});
