import { describe, expect, it } from "vitest";
import { receiptKey } from "./receiptKey";

describe("receiptKey", () => {
  it("withdrawn wins, even over isCurrent", () => {
    expect(receiptKey({ withdrawn: true, isCurrent: false })).toBe("withdrawn");
    expect(receiptKey({ withdrawn: true, isCurrent: true })).toBe("withdrawn");
  });
  it("current when on file", () => expect(receiptKey({ withdrawn: false, isCurrent: true })).toBe("current"));
  it("superseded otherwise", () => expect(receiptKey({ withdrawn: false, isCurrent: false })).toBe("superseded"));
});
