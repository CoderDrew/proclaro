import { describe, expect, it } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import { loadDocContext, SolicitationNotFound } from "./loadDocContext";

type Rows = Record<string, unknown[]>;

/** Minimal chainable stand-in for the Supabase query builder: filters are ignored (rows are pre-scoped). */
function fakeClient(tables: Rows): SupabaseClient<never> {
  const q = (rows: unknown[]) => {
    const b: Record<string, unknown> = {};
    const res = { data: rows, error: null };
    b.select = () => b;
    b.eq = () => b;
    b.single = () => Promise.resolve({ data: rows[0] ?? null, error: null });
    b.maybeSingle = b.single;
    b.then = (f: (v: unknown) => unknown) => Promise.resolve(res).then(f);
    return b;
  };
  return { from: (t: string) => q(tables[t] ?? []) } as unknown as SupabaseClient<never>;
}

const base: Rows = {
  solicitations: [{ id: "s1", agency_id: "a1", number: null, version: null, data: { shortTitle: "Roof" } }],
  settings: [{ state_name: "State of Calder", office_name: "Calder State Construction Office", timezone: "America/Denver" }],
  organizations: [{ name: "Calder Department of Example" }],
  clauses: [
    { key: "award", version: 1, body: "old" },
    { key: "award", version: 2, body: "new" },
    { key: "bonds", version: 1, body: "bonds v1" },
  ],
};

describe("loadDocContext", () => {
  it("uses the latest clause versions without locks", async () => {
    const ctx = await loadDocContext(fakeClient(base), "s1", { useLocks: false });
    expect(ctx.clauses).toEqual({ award: "new", bonds: "bonds v1" });
    expect(ctx.agencyName).toBe("Calder Department of Example");
    expect(ctx.data.shortTitle).toBe("Roof");
    expect(ctx.data.bidValidityDays).toBe(90);
  });

  it("uses locked versions with locks, and latest for unlocked keys", async () => {
    const tables = { ...base, solicitation_clause_locks: [{ clause_key: "award", clause_version: 1 }] };
    const ctx = await loadDocContext(fakeClient(tables), "s1", { useLocks: true });
    expect(ctx.clauses).toEqual({ award: "old", bonds: "bonds v1" });
  });

  it("with useLocks, a solicitation that has locks previews the locked text, not the Admin's later edit", async () => {
    const tables = { ...base, solicitation_clause_locks: [{ clause_key: "award", clause_version: 1 }] };
    const ctx = await loadDocContext(fakeClient(tables), "s1", { useLocks: true });
    expect(ctx.clauses).toEqual({ award: "old", bonds: "bonds v1" });
  });

  it("with useLocks, a draft with no lock rows still gets the latest text", async () => {
    const ctx = await loadDocContext(fakeClient(base), "s1", { useLocks: true });
    expect(ctx.clauses).toEqual({ award: "new", bonds: "bonds v1" });
  });

  it("throws when a locked clause version is missing", async () => {
    const tables = { ...base, solicitation_clause_locks: [{ clause_key: "award", clause_version: 7 }] };
    await expect(loadDocContext(fakeClient(tables), "s1", { useLocks: true })).rejects.toThrow(/award.*7/);
  });

  it("throws SolicitationNotFound when RLS hides the row", async () => {
    await expect(loadDocContext(fakeClient({ ...base, solicitations: [] }), "s1", { useLocks: false }))
      .rejects.toBeInstanceOf(SolicitationNotFound);
  });
});
