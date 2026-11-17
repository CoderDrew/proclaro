import { describe, expect, it, vi } from "vitest";
import type { SessionContext } from "@/lib/session";
import { saveClause, type ClauseDeps } from "./logic";

const admin: SessionContext = { userId: "u-admin", orgId: "o1", orgKind: "office", isAdmin: true, displayName: "Admin" };
const staff: SessionContext = { ...admin!, userId: "u-staff", isAdmin: false };

function deps(over: Partial<ClauseDeps> = {}) {
  return {
    latest: vi.fn(async () => ({ version: 3, body: "old text" }) as { version: number; body: string } | null),
    insert: vi.fn(async () => "ok" as "ok" | "conflict"),
    ...over,
  } satisfies ClauseDeps;
}

describe("saveClause", () => {
  it("rejects an unknown variable and names it", async () => {
    const d = deps();
    const r = await saveClause(admin, "notice", "Hello {{bogus}}", d);
    expect(r.ok).toBe(false);
    expect(!r.ok && r.message).toContain("bogus");
    expect(d.insert).not.toHaveBeenCalled();
  });

  it("accepts every legitimate variable", async () => {
    const body = "{{stateName}} {{officeName}} {{agencyName}} {{number}} {{bidDueDate}} {{bidDueTime}} {{questionsDue}} {{answersDue}} {{bidValidityDays}}";
    expect((await saveClause(admin, "notice", body, deps())).ok).toBe(true);
  });

  it("rejects a key outside CLAUSE_KEYS", async () => {
    const d = deps();
    const r = await saveClause(admin, "unknown_key", "x", d);
    expect(r.ok).toBe(false);
    expect(d.insert).not.toHaveBeenCalled();
  });

  it("inserts previous + 1, attributed to the caller", async () => {
    const d = deps();
    const r = await saveClause(admin, "insurance", "New insurance text.", d);
    expect(r.ok).toBe(true);
    expect(d.insert).toHaveBeenCalledWith({ key: "insurance", version: 4, body: "New insurance text.", createdBy: "u-admin" });
  });

  it("refuses a non-admin and a signed-out caller without touching the database", async () => {
    for (const ctx of [staff, null]) {
      const d = deps();
      const r = await saveClause(ctx, "notice", "x", d);
      expect(r.ok).toBe(false);
      expect(d.latest).not.toHaveBeenCalled();
      expect(d.insert).not.toHaveBeenCalled();
    }
  });

  it("rejects blank text and text identical to the current version", async () => {
    expect((await saveClause(admin, "notice", "   ", deps())).ok).toBe(false);
    const d = deps();
    const r = await saveClause(admin, "notice", "old text", d);
    expect(r.ok).toBe(false);
    expect(d.insert).not.toHaveBeenCalled();
  });

  it("retries at the next version when a concurrent save took the same one", async () => {
    const latest = vi.fn()
      .mockResolvedValueOnce({ version: 3, body: "old" })
      .mockResolvedValueOnce({ version: 4, body: "someone else" });
    const insert = vi.fn().mockResolvedValueOnce("conflict").mockResolvedValueOnce("ok");
    const r = await saveClause(admin, "notice", "mine", { latest, insert });
    expect(r.ok).toBe(true);
    expect(insert.mock.calls.map((c) => c[0].version)).toEqual([4, 5]);
  });

  it("gives a clear message if the conflict persists", async () => {
    const d = deps({ insert: vi.fn(async () => "conflict" as const) });
    const r = await saveClause(admin, "notice", "mine", d);
    expect(r.ok).toBe(false);
    expect(!r.ok && r.message).toMatch(/another administrator/i);
  });

  it("treats a first-ever save (no versions) as version 1", async () => {
    const d = deps({ latest: vi.fn(async () => null) });
    await saveClause(admin, "notice", "text", d);
    expect(d.insert).toHaveBeenCalledWith(expect.objectContaining({ version: 1 }));
  });
});
