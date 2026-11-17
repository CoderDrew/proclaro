import { describe, expect, it } from "vitest";
import { deriveRequirements } from "./valueBands";
import type { OptionalSection } from "./types";

const r = (d: number, fed = false, opt: OptionalSection[] = []) =>
  deriveRequirements(Math.round(d * 100), fed, opt);

describe("deriveRequirements", () => {
  it("blocks under 50,000.00", () => {
    expect(r(49_999.99).blocked).toBe(true);
    expect(r(50_000).blocked).toBe(false);
  });
  it("prevailing wage at 100,000.00", () => {
    expect(r(99_999.99).prevailingWage).toBe(false);
    expect(r(100_000).prevailingWage).toBe(true);
  });
  it("bonds at 150,000.00", () => {
    expect(r(149_999.99).bonds).toBe(false);
    expect(r(150_000).bonds).toBe(true);
  });
  it("apprentice credit at 1,000,000.00", () => {
    expect(r(999_999.99).apprenticeCredit).toBe(false);
    expect(r(1_000_000).apprenticeCredit).toBe(true);
  });
  it("federal clauses follow federal funds", () => {
    expect(r(200_000, true).federalClauses).toBe(true);
    expect(r(200_000, false).federalClauses).toBe(false);
  });
  it("required sections", () => {
    expect(r(60_000).requiredSections).toEqual(["bid_form_1", "bid_form_2", "signature_page", "insurance"]);
    expect(r(60_000, false, ["references"]).requiredSections).toContain("references");
  });
});
