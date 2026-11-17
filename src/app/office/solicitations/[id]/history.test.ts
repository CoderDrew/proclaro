import { describe, expect, it } from "vitest";
import { describeChanges, formatValue } from "./history";

describe("describeChanges", () => {
  it("shows old and new values with money from cents and readable dates", () => {
    expect(describeChanges([
      { key: "estimateCents", old: 15000000, new: 16000050 },
      { key: "bidDueDate", old: "2026-12-16", new: "2026-12-17" },
      { key: "questionsDue", old: null, new: { date: "2026-12-08", time: "13:00" } },
    ])).toEqual([
      "estimateCents: $150,000.00 → $160,000.50",
      "bidDueDate: Dec 16, 2026 → Dec 17, 2026",
      "questionsDue: (blank) → Dec 8, 2026 13:00",
    ]);
  });
  it("tolerates missing or malformed detail", () => {
    expect(describeChanges(undefined)).toEqual([]);
    expect(formatValue("x", [1, 2])).toBe("[1,2]");
  });
});
