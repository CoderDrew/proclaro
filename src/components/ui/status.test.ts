import { describe, expect, it } from "vitest";
import { statusBadge, type DomainStatus, type StatusTone } from "./status";

const TONES: StatusTone[] = ["success", "danger", "warning", "neutral"];

const rows: [string, DomainStatus, StatusTone, string][] = [
  ["solicitation draft", { kind: "solicitation", state: "draft" }, "neutral", "Draft"],
  ["solicitation submitted", { kind: "solicitation", state: "submitted" }, "warning", "Submitted"],
  ["solicitation in_review", { kind: "solicitation", state: "in_review" }, "warning", "In review"],
  ["solicitation in_check", { kind: "solicitation", state: "in_check" }, "warning", "In check"],
  ["solicitation approved", { kind: "solicitation", state: "approved" }, "success", "Approved"],
  ["solicitation published", { kind: "solicitation", state: "published" }, "success", "Published"],
  ["solicitation unknown", { kind: "solicitation", state: "mystery_state" }, "neutral", "mystery_state"],
  ["bidding Open", { kind: "bidding", status: "Open" }, "success", "Open"],
  ["bidding Closed", { kind: "bidding", status: "Closed" }, "neutral", "Closed"],
  ["bidVersion current", { kind: "bidVersion", status: "current" }, "success", "current"],
  ["bidVersion superseded", { kind: "bidVersion", status: "superseded" }, "neutral", "superseded"],
  ["bidVersion withdrawn", { kind: "bidVersion", status: "withdrawn" }, "neutral", "withdrawn"],
  ["bidVersion unknown", { kind: "bidVersion", status: "weird" }, "neutral", "weird"],
  ["original true", { kind: "original", received: true }, "success", "Received"],
  ["original false", { kind: "original", received: false }, "danger", "Non-responsive"],
  ["files empty", { kind: "files", flags: [] }, "success", "Unaltered"],
  ["files flags", { kind: "files", flags: ["a", "b"] }, "danger", "a; b"],
  ["file ok", { kind: "file", status: "ok" }, "success", "Unaltered"],
  ["file missing", { kind: "file", status: "missing" }, "danger", "missing since submission"],
  ["file changed", { kind: "file", status: "changed" }, "danger", "changed since submission"],
  ["file other", { kind: "file", status: "odd" }, "danger", "odd since submission"],
  ["logEntry afterDue", { kind: "logEntry", flag: "afterDue" }, "warning", "after the bid due time"],
];

describe("statusBadge", () => {
  for (const [name, input, tone, label] of rows) {
    it(name, () => {
      expect(statusBadge(input)).toEqual({ tone, label });
    });
  }

  it("always returns a non-empty label and a known tone", () => {
    for (const [, input] of rows) {
      const r = statusBadge(input);
      expect(r.label.length).toBeGreaterThan(0);
      expect(TONES).toContain(r.tone);
    }
  });

  it("falls back to a readable neutral badge for an empty unknown state", () => {
    const r = statusBadge({ kind: "solicitation", state: "" });
    expect(r.tone).toBe("neutral");
    expect(r.label.length).toBeGreaterThan(0);
  });
});
