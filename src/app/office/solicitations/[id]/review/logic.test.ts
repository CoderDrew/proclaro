import { describe, expect, it, vi } from "vitest";
import {
  GROUND_LABELS, apprenticeLabel, rowLabel, cureView, outcomeEditable, outcomeFormNote, parseOutcomeForm, parseVerifyForm,
  reviewMessageFor, runSendFlags, runSetOutcome, runVerifyResident, sendFlagsEnabled, type ReviewDeps,
  blockerMessages, recapWords, runDisagreeRecap, runPostRecap, runPostRecapAlone, runSendRecapToCheck,
  awardControls, runDisagreeAward, runPostAward, runPostAwardAlone, runSendAwardToCheck,
  recapCheckControls, runRecallAward, runRecallRecap,
} from "./logic";

const BID = "33333333-3333-4333-8333-333333333333";

function deps(over: Partial<ReviewDeps> = {}) {
  return { call: vi.fn(async () => {}), ...over } satisfies ReviewDeps;
}

describe("GROUND_LABELS", () => {
  it("names the three office grounds", () => {
    expect(GROUND_LABELS).toEqual({
      late_upload: "Late upload", wrong_form: "Wrong form", missing_signature: "Missing signature",
    });
  });
});

describe("parseOutcomeForm", () => {
  it("requires the non-responsive reason", () => {
    expect(parseOutcomeForm({ bidId: BID, outcome: "non_responsive", ground: "", note: "x" }))
      .toEqual({ ok: false, message: "Choose the non-responsive reason." });
  });

  it("drops a ground sent with accepted", () => {
    expect(parseOutcomeForm({ bidId: BID, outcome: "accepted", ground: "wrong_form", note: " Looks complete " }))
      .toEqual({ ok: true, value: { bidId: BID, outcome: "accepted", ground: null, note: "Looks complete" } });
  });

  it("keeps the ground for non-responsive", () => {
    expect(parseOutcomeForm({ bidId: BID, outcome: "non_responsive", ground: "missing_signature", note: "No signature" }))
      .toEqual({ ok: true, value: { bidId: BID, outcome: "non_responsive", ground: "missing_signature", note: "No signature" } });
  });

  it("refuses a blank note", () => {
    expect(parseOutcomeForm({ bidId: BID, outcome: "accepted_flagged", ground: "", note: "   " }))
      .toEqual({ ok: false, message: "Enter a reason or note." });
    expect(parseOutcomeForm({ bidId: BID, outcome: "accepted" }))
      .toEqual({ ok: false, message: "Enter a reason or note." });
  });

  it("refuses a missing or unknown outcome", () => {
    expect(parseOutcomeForm({ bidId: BID, note: "x" })).toEqual({ ok: false, message: "Choose an outcome." });
    expect(parseOutcomeForm({ bidId: BID, outcome: "rejected", note: "x" })).toEqual({ ok: false, message: "Choose an outcome." });
  });

  it("refuses an unknown ground and a malformed bid id", () => {
    expect(parseOutcomeForm({ bidId: BID, outcome: "non_responsive", ground: "late", note: "x" }))
      .toEqual({ ok: false, message: "Choose the non-responsive reason." });
    expect(parseOutcomeForm({ bidId: "nope", outcome: "accepted", note: "x" }).ok).toBe(false);
  });
});

describe("parseVerifyForm", () => {
  it("reads the verdict and trimmed note", () => {
    expect(parseVerifyForm({ bidId: BID, verified: "true", note: " Certificate on file " }))
      .toEqual({ ok: true, value: { bidId: BID, verified: true, note: "Certificate on file" } });
    expect(parseVerifyForm({ bidId: BID, verified: "false", note: "Expired" }))
      .toEqual({ ok: true, value: { bidId: BID, verified: false, note: "Expired" } });
  });

  it("requires a verdict and a note", () => {
    expect(parseVerifyForm({ bidId: BID, note: "x" })).toEqual({ ok: false, message: "Choose verified or not verified." });
    expect(parseVerifyForm({ bidId: BID, verified: "true", note: "" })).toEqual({ ok: false, message: "Enter a reason or note." });
  });
});

describe("reviewMessageFor", () => {
  it("words the outcome codes", () => {
    expect(reviewMessageFor({ message: "outcome_locked" })).toBe("This outcome is set automatically and cannot be changed.");
    expect(reviewMessageFor(new Error("invalid_state"))).toBe("Outcomes can no longer be changed at this stage.");
    expect(reviewMessageFor({ message: "same_person" })).toBe("You prepared or reviewed these bids, so a different person must check.");
  });

  it("words recap_stale and cure_pending with the brief's copy", () => {
    expect(reviewMessageFor({ message: "recap_stale" }))
      .toBe("The bids changed after this recap was prepared. Send it back and prepare it again.");
    expect(reviewMessageFor(new Error("cure_pending")))
      .toBe("A bid bond cure is still pending. Wait until the cure deadline.");
  });

  it("words every new and reused code without echoing the code", () => {
    const codes = [
      "snapshot_mismatch", "cure_closed", "outcome_locked", "cure_pending", "undecided_bids", "flags_pending",
      "resident_unverified", "recap_stale", "pick_required", "not_in_recap", "not_authorized", "not_found",
      "invalid_state", "invalid_data", "invalid_bid", "reason_required", "comment_required", "same_person", "sealed",
    ];
    const generic = reviewMessageFor(new Error("something_else"));
    for (const c of codes) {
      const m = reviewMessageFor({ message: c });
      expect(m).not.toBe(generic);
      expect(m).not.toContain("_");
    }
  });

  it("falls back to generic copy", () => {
    expect(reviewMessageFor(undefined)).toBe("Something went wrong. Reload the page and try again.");
    expect(reviewMessageFor("outcome_locked")).toBe("Something went wrong. Reload the page and try again.");
  });
});

describe("runSetOutcome", () => {
  it("calls set_bid_outcome with the parsed values", async () => {
    const d = deps();
    const r = await runSetOutcome({ bidId: BID, outcome: "non_responsive", ground: "late_upload", note: "Late" }, d);
    expect(r.ok).toBe(true);
    expect(d.call).toHaveBeenCalledWith("set_bid_outcome", {
      p_bid_id: BID, p_outcome: "non_responsive", p_ground: "late_upload", p_note: "Late",
    });
  });

  it("never calls the database for invalid input, and words database errors", async () => {
    const d = deps();
    expect((await runSetOutcome({ bidId: BID, outcome: "accepted", note: "" }, d)).ok).toBe(false);
    expect(d.call).not.toHaveBeenCalled();
    const locked = deps({ call: vi.fn(async () => { throw new Error("outcome_locked"); }) });
    expect(await runSetOutcome({ bidId: BID, outcome: "accepted", note: "x" }, locked))
      .toEqual({ ok: false, message: "This outcome is set automatically and cannot be changed." });
  });
});

describe("runVerifyResident", () => {
  it("calls verify_resident and words its stage error for residents", async () => {
    const d = deps();
    expect((await runVerifyResident({ bidId: BID, verified: "true", note: "On file" }, d)).ok).toBe(true);
    expect(d.call).toHaveBeenCalledWith("verify_resident", { p_bid_id: BID, p_verified: true, p_note: "On file" });
    const late = deps({ call: vi.fn(async () => { throw new Error("invalid_state"); }) });
    expect(await runVerifyResident({ bidId: BID, verified: "false", note: "x" }, late))
      .toEqual({ ok: false, message: "Resident findings can no longer be changed at this stage." });
  });
});

describe("row helpers", () => {
  it("allows outcome changes only in bid review and never for automatic statuses", () => {
    expect(outcomeEditable("bid_review", "undecided", null)).toBe(true);
    expect(outcomeEditable("bid_review", "non_responsive", "wrong form")).toBe(true);
    expect(outcomeEditable("bid_review", "flagged", "check bond")).toBe(true);
    expect(outcomeEditable("bid_review", "non_responsive", "signed original not received by the bid due time")).toBe(false);
    expect(outcomeEditable("bid_review", "non_responsive", "bid bond not received by the cure deadline")).toBe(false);
    expect(outcomeEditable("bid_review", "pending_cure", null)).toBe(true);
    expect(outcomeEditable("recap_check", "accepted", null)).toBe(false);
  });

  it("labels the apprentice commitment", () => {
    expect(apprenticeLabel(true)).toBe("Yes");
    expect(apprenticeLabel(false)).toBe("No");
    expect(apprenticeLabel(null)).toBe("—");
  });

  it("shows the cure only when one was due", () => {
    expect(cureView("not_required", null)).toBeNull();
    expect(cureView("ok", null)).toBeNull();
    expect(cureView("pending", "2026-11-20T00:00:00Z")).toEqual({ label: "Bond cure pending", dueAt: "2026-11-20T00:00:00Z" });
    expect(cureView("cured", "2026-11-20T00:00:00Z")).toEqual({ label: "Bond cured", dueAt: "2026-11-20T00:00:00Z" });
    expect(cureView("failed", "2026-11-20T00:00:00Z"))
      .toEqual({ label: "Bond not received by the cure deadline", dueAt: "2026-11-20T00:00:00Z" });
  });
});

describe("rowLabel", () => {
  it("names the bid on each repeated save button", () => {
    expect(rowLabel("saveOutcome", "K7QM-2XVD")).toBe("Save outcome for bid K7QM-2XVD");
    expect(rowLabel("saveFinding", "K7QM-2XVD")).toBe("Save finding for bid K7QM-2XVD");
    expect(rowLabel("saveOutcome", "AAAA-AAAA")).not.toBe(rowLabel("saveOutcome", "K7QM-2XVD"));
  });
});

describe("runSendFlags", () => {
  const SOL = "55555555-5555-4555-8555-555555555555";

  it("calls send_flags_to_agency for the solicitation", async () => {
    const d = deps();
    expect(await runSendFlags({ solicitationId: SOL }, d)).toEqual({ ok: true, message: "Flagged bids sent to the agency." });
    expect(d.call).toHaveBeenCalledWith("send_flags_to_agency", { p_solicitation_id: SOL });
  });

  it("refuses a malformed id without calling the database", async () => {
    const d = deps();
    expect(await runSendFlags({ solicitationId: "x" }, d)).toEqual({ ok: false, message: "That solicitation was not found." });
    expect(d.call).not.toHaveBeenCalled();
  });

  it("words the refusals", async () => {
    const fail = (code: string) => deps({ call: vi.fn(async () => { throw new Error(code); }) });
    expect(await runSendFlags({ solicitationId: SOL }, fail("undecided_bids")))
      .toEqual({ ok: false, message: "Set an outcome for every bid first." });
    expect(await runSendFlags({ solicitationId: SOL }, fail("cure_pending")))
      .toEqual({ ok: false, message: "A bid bond cure is still pending. Wait until the cure deadline." });
    expect(await runSendFlags({ solicitationId: SOL }, fail("invalid_state")))
      .toEqual({ ok: false, message: "No bid is flagged for the agency, or the review has moved on. Reload the page." });
  });
});

describe("sendFlagsEnabled", () => {
  it("needs bid review, no earlier send and a flagged bid", () => {
    expect(sendFlagsEnabled("bid_review", null, ["accepted", "flagged"])).toBe(true);
    expect(sendFlagsEnabled("bid_review", "2026-11-19T20:00:00Z", ["flagged"])).toBe(false);
    expect(sendFlagsEnabled("bid_review", null, ["accepted", "flag_accepted"])).toBe(false);
    expect(sendFlagsEnabled("recap_check", null, ["flagged"])).toBe(false);
  });
});

describe("outcomeFormNote", () => {
  it("warns that a new outcome clears the agency's decision", () => {
    const warn = "The agency has decided this flagged bid. Saving a new outcome clears the agency's decision.";
    expect(outcomeFormNote("bid_review", "flag_accepted", true)).toBe(warn);
    expect(outcomeFormNote("bid_review", "flag_rejected", true)).toBe(warn);
  });

  it("explains a pending cure and a disabled form", () => {
    expect(outcomeFormNote("bid_review", "pending_cure", true)).toMatch(/^The bid bond cure is pending/);
    expect(outcomeFormNote("recap_check", "accepted", false)).toBe("Outcomes can no longer be changed at this stage.");
    expect(outcomeFormNote("bid_review", "non_responsive", false)).toBe("This outcome is set automatically and cannot be changed.");
    expect(outcomeFormNote("bid_review", "accepted", true)).toBeNull();
  });
});

describe("recap workflow", () => {
  const SOL = "66666666-6666-4666-8666-666666666666";
  const fail = (code: string) => deps({ call: vi.fn(async () => { throw new Error(code); }) });

  it("words the recap and the memo", () => {
    expect(recapWords("recap")).toMatchObject({
      send: "Send recap to check", post: "Post recap", alone: "Post alone (no second reviewer available)",
    });
    expect(recapWords("all_rejected")).toMatchObject({
      send: "Send memo to check", post: "Post memo", alone: "Post alone (no second reviewer available)",
    });
  });

  it("lists blockers in plain words, in order", () => {
    expect(blockerMessages(["cure_pending", "undecided_bids"])).toEqual([
      "A bid bond cure is still pending. Wait until the cure deadline.", "Set an outcome for every bid first.",
    ]);
  });

  it("sends to check, posts and posts alone for the solicitation", async () => {
    const d = deps();
    expect(await runSendRecapToCheck({ solicitationId: SOL }, d)).toEqual({ ok: true, message: "Recap sent to check." });
    expect(d.call).toHaveBeenLastCalledWith("send_recap_to_check", { p_solicitation_id: SOL });
    expect(await runPostRecap({ solicitationId: SOL, kind: "all_rejected" }, d)).toEqual({ ok: true, message: "Memo posted." });
    expect(d.call).toHaveBeenLastCalledWith("post_recap", { p_solicitation_id: SOL });
    expect(await runPostRecapAlone({ solicitationId: SOL }, d))
      .toEqual({ ok: true, message: "Recap posted without a second reviewer." });
    expect(d.call).toHaveBeenLastCalledWith("post_recap_alone", { p_solicitation_id: SOL });
  });

  it("disagrees with a trimmed comment and refuses a blank one locally", async () => {
    const d = deps();
    expect(await runDisagreeRecap({ solicitationId: SOL, comment: "  Bid C ground is wrong " }, d))
      .toEqual({ ok: true, message: "Recap sent back to bid review." });
    expect(d.call).toHaveBeenCalledWith("disagree_recap", { p_solicitation_id: SOL, p_comment: "Bid C ground is wrong" });
    const d2 = deps();
    expect(await runDisagreeRecap({ solicitationId: SOL, comment: "  " }, d2)).toEqual({ ok: false, message: "Enter a comment." });
    expect(d2.call).not.toHaveBeenCalled();
  });

  it("refuses a malformed id without calling the database", async () => {
    const d = deps();
    expect(await runPostRecap({ solicitationId: "x" }, d)).toEqual({ ok: false, message: "That solicitation was not found." });
    expect(d.call).not.toHaveBeenCalled();
  });

  it("words the refusals", async () => {
    expect(await runPostRecap({ solicitationId: SOL }, fail("recap_stale"))).toEqual({
      ok: false, message: "The bids changed after this recap was prepared. Send it back and prepare it again.",
    });
    expect(await runPostRecap({ solicitationId: SOL }, fail("same_person")))
      .toEqual({ ok: false, message: "You prepared or reviewed these bids, so a different person must check." });
    expect(await runSendRecapToCheck({ solicitationId: SOL }, fail("cure_pending")))
      .toEqual({ ok: false, message: "A bid bond cure is still pending. Wait until the cure deadline." });
    expect(await runSendRecapToCheck({ solicitationId: SOL }, fail("invalid_state")))
      .toEqual({ ok: false, message: "The recap has moved on since this page loaded. Reload the page." });
    expect(await runDisagreeRecap({ solicitationId: SOL, comment: "x" }, fail("not_found")))
      .toEqual({ ok: false, message: "That solicitation was not found." });
  });
});

describe("award workflow", () => {
  const SOL = "77777777-7777-4777-8777-777777777777";
  const fail = (code: string) => deps({ call: vi.fn(async () => { throw new Error(code); }) });
  it("calls the award functions and words the success", async () => {
    const d = deps();
    expect(await runSendAwardToCheck({ solicitationId: SOL }, d)).toEqual({ ok: true, message: "Award sent to check." });
    expect(d.call).toHaveBeenLastCalledWith("send_award_to_check", { p_solicitation_id: SOL });
    expect(await runPostAward({ solicitationId: SOL }, d)).toEqual({ ok: true, message: "Award posted." });
    expect(d.call).toHaveBeenLastCalledWith("post_award", { p_solicitation_id: SOL });
    expect(await runPostAwardAlone({ solicitationId: SOL }, d))
      .toEqual({ ok: true, message: "Award posted without a second reviewer." });
    expect(d.call).toHaveBeenLastCalledWith("post_award_alone", { p_solicitation_id: SOL });
  });

  it("disagrees with a trimmed comment and refuses a blank one locally", async () => {
    const d = deps();
    expect(await runDisagreeAward({ solicitationId: SOL, comment: " Confirm the start date " }, d))
      .toEqual({ ok: true, message: "Award sent back. The agency can change its choice." });
    expect(d.call).toHaveBeenCalledWith("disagree_award", { p_solicitation_id: SOL, p_comment: "Confirm the start date" });
    const d2 = deps();
    expect(await runDisagreeAward({ solicitationId: SOL, comment: "" }, d2)).toEqual({ ok: false, message: "Enter a comment." });
    expect(await runPostAward({ solicitationId: "x" }, d2)).toEqual({ ok: false, message: "That solicitation was not found." });
    expect(d2.call).not.toHaveBeenCalled();
  });

  it("words the refusals", async () => {
    expect(await runPostAward({ solicitationId: SOL }, fail("same_person")))
      .toEqual({ ok: false, message: "You sent this award to check, so a different office user must check it." });
    expect(await runSendAwardToCheck({ solicitationId: SOL }, fail("pick_required")))
      .toEqual({ ok: false, message: "Choose the bid to award." });
    expect(await runPostAward({ solicitationId: SOL }, fail("invalid_state")))
      .toEqual({ ok: false, message: "The award has moved on since this page loaded. Reload the page." });
  });
});

describe("awardControls", () => {
  it("recap_posted: send and post alone need the agency's pick", () => {
    expect(awardControls("recap_posted", false, false))
      .toEqual({ send: false, alone: false, check: false, recall: false,
        note: "The agency has not chosen a bid from the recap yet." });
    expect(awardControls("recap_posted", true, false)).toMatchObject({ send: true, alone: true, check: false });
  });

  it("recap_posted after a disagreement: send and post alone wait for a new pick", () => {
    expect(awardControls("recap_posted", true, false, true)).toEqual({
      send: false, alone: false, check: false, recall: false, note: "Ask the agency to record a new award choice first.",
    });
    expect(awardControls("recap_posted", true, false, false)).toMatchObject({ send: true, alone: true });
  });

  it("send and post alone word invalid_state as the new-pick rule; post keeps the stage wording", async () => {
    const fail = (code: string) => deps({ call: vi.fn(async () => { throw new Error(code); }) });
    const sol = "88888888-8888-4888-8888-888888888888";
    const msg = "Ask the agency to record a new award choice first. If it already has, reload the page.";
    expect(await runSendAwardToCheck({ solicitationId: sol }, fail("invalid_state"))).toEqual({ ok: false, message: msg });
    expect(await runPostAwardAlone({ solicitationId: sol }, fail("invalid_state"))).toEqual({ ok: false, message: msg });
    expect(await runPostAward({ solicitationId: sol }, fail("invalid_state")))
      .toEqual({ ok: false, message: "The award has moved on since this page loaded. Reload the page." });
  });

  it("award_check: only a checker who is not this round's sender can post or disagree", () => {
    expect(awardControls("award_check", true, true)).toMatchObject({ send: false, alone: false, check: true });
    expect(awardControls("award_check", true, false)).toEqual({
      send: false, alone: false, check: false,
      recall: true,
      note: "You sent this award to check, so a different office user must post it or send it back. If no one else can, recall it; posting alone is then recorded.",
    });
  });

  it("other stages: nothing is enabled", () => {
    for (const s of ["bid_review", "recap_check", "awarded", "all_rejected"]) {
      expect(awardControls(s, true, true)).toMatchObject({ send: false, alone: false, check: false, recall: false });
      expect(awardControls(s, true, false)).toMatchObject({ recall: false });
    }
  });
});

describe("recall (Ruling 13)", () => {
  const SOL = "99999999-9999-4999-8999-999999999999";
  const fail = (code: string) => deps({ call: vi.fn(async () => { throw new Error(code); }) });

  it("recalls the recap or memo and the award", async () => {
    const d = deps();
    expect(await runRecallRecap({ solicitationId: SOL }, d)).toEqual({ ok: true, message: "Recap recalled to bid review." });
    expect(d.call).toHaveBeenLastCalledWith("recall_recap", { p_solicitation_id: SOL });
    expect(await runRecallRecap({ solicitationId: SOL, kind: "all_rejected" }, d))
      .toEqual({ ok: true, message: "Memo recalled to bid review." });
    expect(await runRecallAward({ solicitationId: SOL }, d))
      .toEqual({ ok: true, message: "Award recalled. You can send it to check again or post it alone." });
    expect(d.call).toHaveBeenLastCalledWith("recall_award", { p_solicitation_id: SOL });
  });

  it("refuses a malformed id locally and words the refusals", async () => {
    const d = deps();
    expect(await runRecallRecap({ solicitationId: "x" }, d)).toEqual({ ok: false, message: "That solicitation was not found." });
    expect(await runRecallAward({ solicitationId: "x" }, d)).toEqual({ ok: false, message: "That solicitation was not found." });
    expect(d.call).not.toHaveBeenCalled();
    expect(await runRecallRecap({ solicitationId: SOL }, fail("not_authorized")))
      .toEqual({ ok: false, message: "Only the office user who sent the recap to check can recall it." });
    expect(await runRecallAward({ solicitationId: SOL }, fail("not_authorized")))
      .toEqual({ ok: false, message: "Only the office user who sent the award to check can recall it." });
    expect(await runRecallRecap({ solicitationId: SOL }, fail("invalid_state")))
      .toEqual({ ok: false, message: "The recap has moved on since this page loaded. Reload the page." });
    expect(await runRecallAward({ solicitationId: SOL }, fail("invalid_state")))
      .toEqual({ ok: false, message: "The award has moved on since this page loaded. Reload the page." });
  });

  it("recapCheckControls: a checker, the sender, or a past reviewer", () => {
    expect(recapCheckControls(true, false, "recap", "Office One")).toEqual({
      check: true, recall: false,
      note: "Prepared by Office One. Check it against the bids, then post it or send it back. Posting makes it public.",
    });
    expect(recapCheckControls(false, true, "all_rejected", "Office One")).toMatchObject({ check: false, recall: true });
    expect(recapCheckControls(false, true, "all_rejected", null).note).toContain("You sent this memo to check");
    expect(recapCheckControls(false, false, "recap", null)).toEqual({
      check: false, recall: false,
      note: "Prepared by another office user. You prepared or reviewed these bids, so a different office user must post it or send it back.",
    });
  });

  it("words the recap and memo post confirmations", () => {
    expect(recapWords("recap")).toMatchObject({
      postConfirm: "Confirm: post recap publicly", warning: "This makes the recap public and can't be undone.",
    });
    expect(recapWords("all_rejected")).toMatchObject({
      postConfirm: "Confirm: post memo publicly",
      aloneConfirm: "Confirm: post memo publicly without a second reviewer",
      warning: "This makes the memo public, rejects every bid and can't be undone.",
    });
  });
});
