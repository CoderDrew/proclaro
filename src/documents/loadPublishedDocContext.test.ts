import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { loadPublishedDocContext } from "./loadPublishedDocContext";
import { SolicitationNotFound } from "./loadDocContext";

type Rows = Record<string, unknown[]>;
function fakeClient(tables: Rows, touched: string[] = []): SupabaseClient<never> {
  const q = (rows: unknown[]) => {
    const b: Record<string, unknown> = {};
    b.select = () => b;
    b.eq = () => b;
    b.single = () => Promise.resolve({ data: rows[0] ?? null, error: null });
    b.maybeSingle = b.single;
    b.then = (f: (v: unknown) => unknown) => Promise.resolve({ data: rows, error: null }).then(f);
    return b;
  };
  return { from: (t: string) => { touched.push(t); return q(tables[t] ?? []); } } as unknown as SupabaseClient<never>;
}

const snapshot = {
  data: { shortTitle: "Roof" },
  clauses: { award: "as published" },
  settings: { stateName: "State of Calder", officeName: "Calder State Construction Office", timezone: "America/Denver" },
};
const tables: Rows = {
  solicitations: [{ id: "s1", agency_id: "a1", number: "27-0001", version: 1, published_snapshot: snapshot }],
  organizations: [{ name: "Calder Department of Example" }],
  clauses: [{ key: "award", version: 2, body: "edited after publishing" }],
};

describe("loadPublishedDocContext", () => {
  it("uses the snapshot's clauses even when the clauses table holds a newer version, and never reads it", async () => {
    const touched: string[] = [];
    const ctx = await loadPublishedDocContext(fakeClient(tables, touched), "s1");
    expect(ctx.clauses).toEqual({ award: "as published" });
    expect(touched).not.toContain("clauses");
    expect(touched).not.toContain("solicitation_clause_locks");
    expect(ctx.number).toBe("27-0001");
    expect(ctx.version).toBe(1);
    expect(ctx.agencyName).toBe("Calder Department of Example");
    expect(ctx.data.shortTitle).toBe("Roof");
    expect(ctx.settings.timezone).toBe("America/Denver");
  });
  it("throws SolicitationNotFound for an invisible or unpublished solicitation", async () => {
    await expect(loadPublishedDocContext(fakeClient({}), "s1")).rejects.toBeInstanceOf(SolicitationNotFound);
    const unpublished = { ...tables, solicitations: [{ ...(tables.solicitations[0] as object), published_snapshot: null }] };
    await expect(loadPublishedDocContext(fakeClient(unpublished), "s1")).rejects.toBeInstanceOf(SolicitationNotFound);
  });
});
