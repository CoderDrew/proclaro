import { describe, expect, it } from "vitest";
import { score } from "./score";

describe("score", () => {
  it("counts false met separately from false not met", () => {
    const s = score([
      { code: "a", expected: "met", actual: "met" },
      { code: "a", expected: "not_met", actual: "met" },      // false met
      { code: "b", expected: "not_met", actual: "not_met" },
      { code: "b", expected: "met", actual: "not_met" },      // false not met
      { code: "b", expected: "not_met", actual: "unclear" },  // safe miss
      { code: "c", expected: "unclear", actual: "met" },      // false met
    ]);
    expect(s.total).toBe(6);
    expect(s.correct).toBe(2);
    expect(s.falseMet).toBe(2);
    expect(s.falseNotMet).toBe(1);
    expect(s.unclear).toBe(1);
    expect(s.falseMetRate).toBeCloseTo(2 / 4);   // of the 4 cases that shouldn't be met
    expect(s.falseNotMetRate).toBeCloseTo(1 / 2); // of the 2 cases that should be met
    expect(s.byCode.a).toEqual({ total: 2, correct: 1, falseMet: 1, falseNotMet: 0, unclear: 0 });
  });
  it("handles no cases", () => {
    expect(score([])).toMatchObject({ total: 0, falseMetRate: 0, falseNotMetRate: 0 });
  });
});
