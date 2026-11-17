import { describe, it, expect } from "vitest";
import { parseMoney, formatMoney } from "./money";

describe("money", () => {
  it("parses valid input", () => {
    expect(parseMoney("$150,000")).toBe(15_000_000);
    expect(parseMoney("150000.00")).toBe(15_000_000);
    expect(parseMoney("49,999.99")).toBe(4_999_999);
    expect(parseMoney("0.5")).toBe(50);
  });
  it("rejects invalid input", () => {
    expect(parseMoney("12.345")).toBeNull();
    expect(parseMoney("abc")).toBeNull();
    expect(parseMoney("")).toBeNull();
    expect(parseMoney("$")).toBeNull();
    expect(parseMoney("-5")).toBeNull();
  });
  it("formats", () => {
    expect(formatMoney(15_000_000)).toBe("$150,000.00");
    expect(formatMoney(5)).toBe("$0.05");
  });
});
