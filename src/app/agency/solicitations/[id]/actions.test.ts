import { describe, expect, it, vi } from "vitest";
import { emptySolicitation } from "@/domain/solicitation/schema";
import type { SolicitationData } from "@/domain/solicitation/types";
import { appendAttachment, prepareDraftData, runSubmit, safeFileName, type SubmitDeps } from "./logic";

const ID = "11111111-1111-4111-8111-111111111111";

/** A draft that passes every rule on a Wednesday-free schedule (bid due is a Tuesday). */
function validData(over: Partial<SolicitationData> = {}): SolicitationData {
  return {
    ...emptySolicitation(),
    shortTitle: "Roof repair", longTitle: "Roof repair at the Calder Parks maintenance yard",
    category: "major_maintenance", summary: "Replace the roof.", projectDescription: "Replace the roof membrane.",
    location: { address: "1 Example Way", city: "Calder City", county: "Calder" },
    requester: { name: "Pat Example", email: "pat@example.test", phone: "555-0100" },
    projectManager: { name: "Sam Example", email: "sam@example.test", phone: "555-0101" },
    estimateCents: 15_000_000, fundingSource: "major_maintenance", federalFunds: false,
    releaseDate: "2027-01-12", adStart: "2027-01-12", adEnd: "2027-01-28", newspapers: "Calder Courier",
    questionsDue: { date: "2027-01-20", time: "13:00" }, answersDue: { date: "2027-01-22", time: "13:00" },
    bidDueDate: "2027-02-02",
    schedule: { items: [{ name: "Base bid", description: "" }], alternates: [] },
    attachments: [
      { kind: "plans", label: "Plans", storagePath: `solicitations/${ID}/a.pdf`, issueDate: "2027-01-01" },
      { kind: "specifications", label: "Specs", storagePath: `solicitations/${ID}/b.pdf`, issueDate: "2027-01-01" },
      { kind: "sample_contract", label: "Contract", storagePath: `solicitations/${ID}/c.pdf`, issueDate: null },
      { kind: "prevailing_wage", label: "Wages", storagePath: `solicitations/${ID}/d.pdf`, issueDate: null },
    ],
    ...over,
  };
}

function deps(data: SolicitationData, over: Partial<SubmitDeps> = {}) {
  const d = {
    loadData: vi.fn(async () => ({ data, state: "draft" })),
    validationContext: vi.fn(async () => ({ tz: "America/Denver", holidays: [], submissionDate: "2027-01-05" })),
    loadAcks: vi.fn(async () => [] as { code: string; field: string | null }[]),
    submit: vi.fn(async () => {}),
    ...over,
  };
  return d;
}

describe("runSubmit", () => {
  it("returns the errors and does not submit when validation has errors", async () => {
    const d = deps(validData({ shortTitle: "" }));
    const r = await runSubmit(ID, d);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.errors.map((e) => e.field)).toContain("shortTitle");
    expect(d.submit).not.toHaveBeenCalled();
  });

  it("returns unacknowledged warnings and does not submit", async () => {
    // 2027-02-06 is a Saturday: non-working-day warning.
    const d = deps(validData({ bidDueDate: "2027-02-06" }));
    const r = await runSubmit(ID, d);
    expect(r.ok).toBe(false);
    if (!r.ok) {
      expect(r.errors).toEqual([]);
      expect(r.unacknowledged).toEqual([expect.objectContaining({ code: "bid_due_non_working_day", field: "bidDueDate" })]);
    }
    expect(d.submit).not.toHaveBeenCalled();
  });

  it("submits when the warning is acknowledged for the same code and field", async () => {
    const d = deps(validData({ bidDueDate: "2027-02-06" }), {
      loadAcks: vi.fn(async () => [{ code: "bid_due_non_working_day", field: "bidDueDate" }]),
    });
    expect(await runSubmit(ID, d)).toEqual({ ok: true });
    expect(d.submit).toHaveBeenCalledWith(ID);
  });

  it("does not accept an acknowledgment for a different field", async () => {
    const d = deps(validData({ bidDueDate: "2027-02-06" }), {
      loadAcks: vi.fn(async () => [{ code: "bid_due_non_working_day", field: "other" }]),
    });
    const r = await runSubmit(ID, d);
    expect(r.ok).toBe(false);
    expect(d.submit).not.toHaveBeenCalled();
  });

  it("calls submit when clean", async () => {
    const d = deps(validData());
    expect(await runSubmit(ID, d)).toEqual({ ok: true });
    expect(d.submit).toHaveBeenCalledTimes(1);
    expect(d.submit).toHaveBeenCalledWith(ID);
  });

  it("validates the stored row from deps.loadData, and takes no client data", async () => {
    const d = deps(validData({ shortTitle: "" }));
    expect(runSubmit.length).toBe(2); // (id, deps): nothing else can carry client data
    await runSubmit(ID, d);
    expect(d.loadData).toHaveBeenCalledWith(ID);
  });

  it("throws not_found when the row is not visible to the caller", async () => {
    const d = deps(validData(), { loadData: vi.fn(async () => null) });
    await expect(runSubmit(ID, d)).rejects.toThrow("not_found");
    expect(d.submit).not.toHaveBeenCalled();
  });

  it("throws invalid_state for a row that is no longer a draft", async () => {
    const d = deps(validData(), { loadData: vi.fn(async () => ({ data: validData(), state: "submitted" })) });
    await expect(runSubmit(ID, d)).rejects.toThrow("invalid_state");
    expect(d.submit).not.toHaveBeenCalled();
  });
});

describe("prepareDraftData", () => {
  it("rejects data that fails the schema", () => {
    expect(() => prepareDraftData(ID, { ...emptySolicitation(), bidValidityDays: -1 })).toThrow();
    expect(() => prepareDraftData(ID, { nope: true })).toThrow();
  });

  it("rejects attachment paths outside this solicitation's folder", () => {
    const bad = validData({
      attachments: [{ kind: "plans", label: "x", storagePath: "solicitations/22222222-2222-4222-8222-222222222222/a.pdf", issueDate: null }],
    });
    expect(() => prepareDraftData(ID, bad)).toThrow("invalid_attachment_path");
  });

  it("returns parsed data for a good draft", () => {
    const good = validData();
    expect(prepareDraftData(ID, good)).toEqual(good);
  });
});

describe("safeFileName", () => {
  it("keeps a plain name and strips path and odd characters", () => {
    expect(safeFileName("Plans v2.pdf")).toBe("Plans_v2.pdf");
    expect(safeFileName("../../etc/pass wd?.pdf")).toBe("pass_wd_.pdf");
    expect(safeFileName("")).toBe("file");
  });
});

describe("appendAttachment", () => {
  const att = (n: string) => ({ kind: "plans" as const, label: n, storagePath: `solicitations/${ID}/${n}.pdf`, issueDate: null });

  it("keeps both attachments when two uploads complete from the same stale snapshot", () => {
    const stale = validData({ attachments: [] });
    // Upload A and B both started from `stale`; they complete one after the other against the latest state.
    const afterA = appendAttachment(stale, att("a"));
    const afterB = appendAttachment(afterA, att("b"));
    expect(afterB.attachments.map((a) => a.label)).toEqual(["a", "b"]);
  });

  it("keeps edits and removals made while the upload was in flight", () => {
    const before = validData();
    const latest = { ...before, attachments: before.attachments.slice(1).map((a) => ({ ...a, label: "renamed" })) };
    const next = appendAttachment(latest, att("new"));
    expect(next.attachments).toHaveLength(latest.attachments.length + 1);
    expect(next.attachments.slice(0, -1).every((a) => a.label === "renamed")).toBe(true);
    expect(next.attachments.some((a) => a.kind === "plans" && a.label === "Plans")).toBe(false);
  });
});
