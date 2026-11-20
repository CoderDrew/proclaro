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
  ["evaluation bid_review", { kind: "evaluation", stage: "bid_review", awaitingAgency: false }, "warning", "Bid review"],
  ["evaluation awaiting agency", { kind: "evaluation", stage: "bid_review", awaitingAgency: true }, "warning", "Awaiting agency"],
  ["evaluation recap_check", { kind: "evaluation", stage: "recap_check", awaitingAgency: false }, "warning", "Recap in check"],
  ["evaluation recap_posted", { kind: "evaluation", stage: "recap_posted", awaitingAgency: false }, "warning", "Award pending"],
  ["evaluation award_check", { kind: "evaluation", stage: "award_check", awaitingAgency: false }, "warning", "Award in check"],
  ["evaluation awarded", { kind: "evaluation", stage: "awarded", awaitingAgency: false }, "success", "Awarded"],
  ["evaluation all_rejected", { kind: "evaluation", stage: "all_rejected", awaitingAgency: false }, "danger", "All bids rejected"],
  ["evaluation unknown", { kind: "evaluation", stage: "odd_stage", awaitingAgency: false }, "neutral", "odd_stage"],
  ["evaluation awaiting only applies in bid review", { kind: "evaluation", stage: "awarded", awaitingAgency: true }, "success", "Awarded"],
  ["review accepted", { kind: "review", status: "accepted" }, "success", "Accepted"],
  ["review flagged", { kind: "review", status: "flagged" }, "warning", "Flagged for agency"],
  ["review flag_accepted", { kind: "review", status: "flag_accepted" }, "success", "Accepted by agency"],
  ["review flag_rejected", { kind: "review", status: "flag_rejected" }, "danger", "Rejected by agency"],
  ["review non_responsive", { kind: "review", status: "non_responsive" }, "danger", "Non-responsive"],
  ["review pending_cure", { kind: "review", status: "pending_cure" }, "warning", "Pending cure"],
  ["review undecided", { kind: "review", status: "undecided" }, "neutral", "Not reviewed"],
  ["review unknown", { kind: "review", status: "mystery" }, "neutral", "mystery"],
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
    expect(statusBadge({ kind: "evaluation", stage: " ", awaitingAgency: false }).label).toBe("Unknown");
    expect(statusBadge({ kind: "review", status: "" }).label).toBe("Unknown");
  });
});
