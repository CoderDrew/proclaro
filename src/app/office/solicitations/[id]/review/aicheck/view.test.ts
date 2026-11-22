import { describe, expect, it } from "vitest";
import { groupItems, parseCheck, runLabel, summary } from "./view";
import { statusBadge } from "@/components/ui/status";

const item = (over: Record<string, unknown>) => ({
  id: "i", documentKind: "insurance", documentPath: "p", code: "insured_name", method: "rule", result: "met",
  page: 1, excerpt: "x", extracted: null, detail: null, callFailed: false, review: null, ...over,
});

describe("parseCheck", () => {
  it("reads bid_ai_check's JSON", () => {
    const v = parseCheck({ run: { id: "r", status: "done", startedAt: "2026-11-21T10:00:00Z", finishedAt: null,
      model: "m", recorded: true, startedByMe: false }, items: [item({})], runsUsed: 1, runsLeft: 2,
      callsLeftUser: 49, callsLeftTotal: 199 });
    expect(v.run?.recorded).toBe(true);
    expect(v.items).toHaveLength(1);
    expect(v.runsLeft).toBe(2);
  });
  it("treats nothing as no run", () => {
    expect(parseCheck(null)).toEqual({ run: null, items: [], runsUsed: 0, runsLeft: 0, callsLeftUser: 0, callsLeftTotal: 0 });
  });
});

describe("groupItems", () => {
  it("groups by document in checklist order, with labels", () => {
    const groups = groupItems([
      item({ id: "a", documentKind: "insurance", code: "insured_name" }),
      item({ id: "b", documentKind: "signed_form", code: "signature_present", method: "ai", documentPath: null }),
      item({ id: "c", documentKind: "insurance", code: "coverage_dates" }),
    ].map((i) => parseCheck({ items: [i] }).items[0]));
    expect(groups.map((g) => g.kind)).toEqual(["signed_form", "insurance"]);
    expect(groups[0].label).toBe("Signed bid form (scan)");
    expect(groups[1].items.map((i) => i.label)).toEqual(["Insured name matches the bidder", "Coverage in force on the bid due date"]);
  });
});

describe("summary and labels", () => {
  it("counts not met and unclear", () => {
    const items = parseCheck({ items: [item({ result: "not_met" }), item({ result: "unclear" }), item({ result: "unclear" }),
      item({ result: "met" })] }).items;
    expect(summary(items)).toBe("1 not met · 2 unclear");
  });
  it("labels runs", () => {
    expect(runLabel({ id: "r", status: "done", startedAt: "", finishedAt: null, model: "m", recorded: true, startedByMe: false }))
      .toBe("Recorded result");
    expect(runLabel({ id: "r", status: "failed", startedAt: "", finishedAt: null, model: "m", recorded: false, startedByMe: true }))
      .toBe("Failed");
    expect(runLabel(null)).toBe("Not run");
  });
  it("badges results with words, never colour alone", () => {
    expect(statusBadge({ kind: "aiCheck", result: "met" })).toEqual({ tone: "success", label: "Met" });
    expect(statusBadge({ kind: "aiCheck", result: "not_met" })).toEqual({ tone: "danger", label: "Not met" });
    expect(statusBadge({ kind: "aiCheck", result: "unclear" })).toEqual({ tone: "warning", label: "Unclear" });
  });
});
