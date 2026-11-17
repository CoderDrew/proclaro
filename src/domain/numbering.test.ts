import { describe, it, expect } from "vitest";
import { formatSolicitationNumber } from "./numbering";

describe("numbering", () => {
  it("formats YY-NNNN", () => {
    expect(formatSolicitationNumber(2027, 674)).toBe("27-0674");
    expect(formatSolicitationNumber(2027, 1)).toBe("27-0001");
    expect(formatSolicitationNumber(2100, 12345)).toBe("00-12345");
  });
});
