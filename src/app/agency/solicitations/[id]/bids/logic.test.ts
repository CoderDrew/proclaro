import { describe, expect, it, vi } from "vitest";
import {
  DECISION_LABELS, canDecide, canPick, parsePick, pickMessageFor, pickReasonRule, runPickAward, type PickDeps, decisionStatus, flaggedMessageFor, parseDecisionForm, rowLabel, runDecideFlagged,
  type FlaggedDeps,
} from "./logic";

const OUTCOME = "44444444-4444-4444-8444-444444444444";

function deps(over: Partial<FlaggedDeps> = {}) {
  return { decide: vi.fn(async () => {}), ...over } satisfies FlaggedDeps;
}

describe("parseDecisionForm", () => {
  it("requires accept or reject", () => {
    expect(parseDecisionForm({ outcomeId: OUTCOME, decision: "", reason: "x" }))
      .toEqual({ ok: false, message: "Choose accept or reject." });
    expect(parseDecisionForm({ outcomeId: OUTCOME, decision: "maybe", reason: "x" }))
      .toEqual({ ok: false, message: "Choose accept or reject." });
    expect(parseDecisionForm({ outcomeId: OUTCOME, reason: "x" }))
      .toEqual({ ok: false, message: "Choose accept or reject." });
  });

  it("requires a reason", () => {
    expect(parseDecisionForm({ outcomeId: OUTCOME, decision: "reject", reason: "   " }))
      .toEqual({ ok: false, message: "Enter a reason." });
    expect(parseDecisionForm({ outcomeId: OUTCOME, decision: "accept" }))
      .toEqual({ ok: false, message: "Enter a reason." });
  });

  it("refuses a malformed outcome id", () => {
    expect(parseDecisionForm({ outcomeId: "not-a-uuid", decision: "accept", reason: "x" }))
      .toEqual({ ok: false, message: "That flagged bid was not found. Reload the page and try again." });
  });

  it("trims and accepts a complete form", () => {
    expect(parseDecisionForm({ outcomeId: OUTCOME, decision: "reject", reason: " Missing addendum acknowledgment " }))
      .toEqual({ ok: true, value: { outcomeId: OUTCOME, decision: "reject", reason: "Missing addendum acknowledgment" } });
  });
});

describe("flaggedMessageFor", () => {
  it("words every database code", () => {
    expect(flaggedMessageFor(new Error("not_authorized"))).toBe("You are not allowed to do that.");
    expect(flaggedMessageFor(new Error("reason_required"))).toBe("Enter a reason.");
    expect(flaggedMessageFor(new Error("invalid_data"))).toBe("Choose accept or reject.");
    expect(flaggedMessageFor({ message: "invalid_state" }))
      .toBe("This bid can no longer be decided here. The office may have changed its review. Reload the page.");
    expect(flaggedMessageFor(new Error("sealed")))
      .toBe("Bids are still sealed. Flagged bids can be decided only after the bid due time.");
  });

  it("falls back to a generic message", () => {
    expect(flaggedMessageFor(new Error("connection reset"))).toBe("Something went wrong. Reload the page and try again.");
    expect(flaggedMessageFor(null)).toBe("Something went wrong. Reload the page and try again.");
    expect(flaggedMessageFor(new Error("toString"))).toBe("Something went wrong. Reload the page and try again.");
  });
});

describe("runDecideFlagged", () => {
  it("calls decide_flagged_bid with the parsed form", async () => {
    const d = deps();
    const r = await runDecideFlagged({ outcomeId: OUTCOME, decision: "accept", reason: " Verified " }, d);
    expect(r).toEqual({ ok: true, message: "Decision saved: accepted." });
    expect(d.decide).toHaveBeenCalledWith({ p_outcome_id: OUTCOME, p_decision: "accept", p_reason: "Verified" });
  });

  it("does not call the database for an invalid form", async () => {
    const d = deps();
    expect(await runDecideFlagged({ outcomeId: OUTCOME, decision: "reject", reason: "" }, d))
      .toEqual({ ok: false, message: "Enter a reason." });
    expect(d.decide).not.toHaveBeenCalled();
  });

  it("words a database refusal", async () => {
    const d = deps({ decide: vi.fn(async () => { throw new Error("invalid_state"); }) });
    const r = await runDecideFlagged({ outcomeId: OUTCOME, decision: "reject", reason: "Material" }, d);
    expect(r).toEqual({
      ok: false, message: "This bid can no longer be decided here. The office may have changed its review. Reload the page.",
    });
  });
});

describe("helpers", () => {
  it("labels the two decisions", () => {
    expect(DECISION_LABELS).toEqual({ accept: "Accept the bid", reject: "Reject the bid" });
  });

  it("maps a decision to the review status badge", () => {
    expect(decisionStatus(null)).toBe("flagged");
    expect(decisionStatus("accept")).toBe("flag_accepted");
    expect(decisionStatus("reject")).toBe("flag_rejected");
  });

  it("allows decisions only in bid review after the flags are sent", () => {
    expect(canDecide("bid_review", "2026-11-19T20:00:00Z")).toBe(true);
    expect(canDecide("bid_review", null)).toBe(false);
    expect(canDecide("recap_check", "2026-11-19T20:00:00Z")).toBe(false);
    expect(canDecide(null, null)).toBe(false);
  });

  it("names each row's save button by its bid", () => {
    expect(rowLabel("B-1234")).toBe("Save decision for bid B-1234");
  });
});

const SOL = "55555555-5555-4555-8555-555555555555";
const A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const recap = { rows: [{ bidId: A }, { bidId: B }], expectedWinnerBidId: A };
const tied = { rows: [{ bidId: A }, { bidId: B }], expectedWinnerBidId: null };

describe("parsePick", () => {
  it("takes the expected winner with no reason (reason null)", () => {
    expect(parsePick({ bidId: A, reason: "  " }, recap)).toEqual({ ok: true, value: { bidId: A, reason: null } });
    expect(parsePick({ bidId: A }, recap)).toEqual({ ok: true, value: { bidId: A, reason: null } });
  });

  it("keeps an optional reason for the expected winner, trimmed", () => {
    expect(parsePick({ bidId: A, reason: " Lowest " }, recap)).toEqual({ ok: true, value: { bidId: A, reason: "Lowest" } });
  });

  it("requires a bidder from the recap", () => {
    for (const bidId of [undefined, "", SOL, "not-a-uuid"]) {
      expect(parsePick({ bidId, reason: "x" }, recap)).toEqual({ ok: false, message: "Choose a bidder from the recap." });
    }
  });

  it("requires a reason when the choice differs from the expected award", () => {
    expect(parsePick({ bidId: B, reason: "   " }, recap))
      .toEqual({ ok: false, message: "Explain why this bid differs from the expected award." });
    expect(parsePick({ bidId: B, reason: "A cannot meet the start date" }, recap))
      .toEqual({ ok: true, value: { bidId: B, reason: "A cannot meet the start date" } });
  });

  it("requires a reason for any choice when rank 1 is tied", () => {
    expect(parsePick({ bidId: A, reason: "" }, tied)).toEqual({ ok: false, message: "Explain the choice between tied bids." });
    expect(parsePick({ bidId: B }, tied)).toEqual({ ok: false, message: "Explain the choice between tied bids." });
    expect(parsePick({ bidId: A, reason: "Earlier start" }, tied))
      .toEqual({ ok: true, value: { bidId: A, reason: "Earlier start" } });
  });
});

describe("pickReasonRule", () => {
  it("names why a reason is required", () => {
    expect(pickReasonRule(recap, A)).toBeNull();
    expect(pickReasonRule(recap, B)).toBe("differs");
    expect(pickReasonRule(tied, A)).toBe("tied");
  });
});

describe("runPickAward", () => {
  function pickDeps(over: Partial<PickDeps> = {}) {
    return { postedRecap: vi.fn(async () => recap), pick: vi.fn(async () => {}), ...over } satisfies PickDeps;
  }

  it("calls pick_award with the parsed choice", async () => {
    const d = pickDeps();
    const r = await runPickAward({ solicitationId: SOL, bidId: B, reason: " Start date " }, d);
    expect(r.ok).toBe(true);
    expect(d.postedRecap).toHaveBeenCalledWith(SOL);
    expect(d.pick).toHaveBeenCalledWith({ p_solicitation_id: SOL, p_bid_id: B, p_reason: "Start date" });
  });

  it("sends a null reason for the expected winner", async () => {
    const d = pickDeps();
    await runPickAward({ solicitationId: SOL, bidId: A, reason: "" }, d);
    expect(d.pick).toHaveBeenCalledWith({ p_solicitation_id: SOL, p_bid_id: A, p_reason: null });
  });

  it("refuses before calling the database when the form is wrong", async () => {
    const d = pickDeps();
    expect(await runPickAward({ solicitationId: SOL, bidId: B }, d))
      .toEqual({ ok: false, message: "Explain why this bid differs from the expected award." });
    expect(await runPickAward({ solicitationId: "x", bidId: A }, d)).toMatchObject({ ok: false });
    expect(d.pick).not.toHaveBeenCalled();
  });

  it("refuses when no recap is posted", async () => {
    const d = pickDeps({ postedRecap: vi.fn(async () => null) });
    expect(await runPickAward({ solicitationId: SOL, bidId: A }, d)).toMatchObject({ ok: false });
    expect(d.pick).not.toHaveBeenCalled();
  });

  it("words database refusals", async () => {
    const d = pickDeps({ pick: vi.fn(async () => { throw new Error("invalid_state"); }) });
    expect(await runPickAward({ solicitationId: SOL, bidId: A }, d)).toEqual({
      ok: false, message: "The award can no longer be chosen here. The office may be checking it. Reload the page.",
    });
    expect(pickMessageFor({ message: "not_in_recap" })).toBe("Choose a bidder from the recap.");
    expect(pickMessageFor({ message: "weird" })).toBe("Something went wrong. Reload the page and try again.");
  });
});

describe("canPick", () => {
  it("only while the recap is posted", () => {
    expect(canPick("recap_posted")).toBe(true);
    for (const s of ["bid_review", "recap_check", "award_check", "awarded", "all_rejected", null]) {
      expect(canPick(s)).toBe(false);
    }
  });
});
