import { describe, expect, it, vi } from "vitest";
import { messageFor } from "../../logic";
import {
  ANSWERS_DUE_PASSED, QUESTION_NOT_FOUND, addendumHistory, addendumMessageFor, approveAlone, approveCheck, closeQuestion, disagree,
  officeQuestionStatus, publishWarning, reassign, reopen, returnAddendum, sendToCheck,
  startReview, withOffice, withdraw, type AddendumOfficeDeps,
} from "./logic";

const AID = "33333333-3333-4333-8333-333333333333";
const QID = "44444444-4444-4444-8444-444444444444";
const USER = "22222222-2222-4222-8222-222222222222";

function deps(err?: string) {
  return {
    call: vi.fn(async () => {
      if (err) throw new Error(err);
    }),
  } satisfies AddendumOfficeDeps;
}

describe("review actions call the addendum functions with their exact arguments", () => {
  const cases = [
    ["startReview", (d: AddendumOfficeDeps) => startReview(AID, d), "start_addendum_review", { p_addendum_id: AID }],
    ["reassign", (d: AddendumOfficeDeps) => reassign(AID, USER, d), "reassign_addendum_review",
      { p_addendum_id: AID, p_user: USER }],
    ["sendToCheck", (d: AddendumOfficeDeps) => sendToCheck(AID, d), "send_addendum_to_check", { p_addendum_id: AID }],
    ["approveCheck", (d: AddendumOfficeDeps) => approveCheck(AID, d), "approve_addendum_check", { p_addendum_id: AID }],
    ["approveAlone", (d: AddendumOfficeDeps) => approveAlone(AID, d), "approve_addendum_alone", { p_addendum_id: AID }],
    ["disagree", (d: AddendumOfficeDeps) => disagree(AID, "  Name the sheet.  ", d), "disagree_addendum",
      { p_addendum_id: AID, p_comment: "Name the sheet." }],
    ["reopen", (d: AddendumOfficeDeps) => reopen(AID, " Fix the date ", d), "reopen_addendum_review",
      { p_addendum_id: AID, p_reason: "Fix the date" }],
    ["withdraw", (d: AddendumOfficeDeps) => withdraw(AID, " Superseded ", d), "withdraw_addendum",
      { p_addendum_id: AID, p_reason: "Superseded" }],
    ["returnAddendum", (d: AddendumOfficeDeps) => returnAddendum(AID, [{ field: " narrative ", body: " Say why. " },
      { field: "", body: "General" }], d), "return_addendum",
      { p_addendum_id: AID, p_comments: [{ field: "narrative", body: "Say why." }, { field: null, body: "General" }] }],
    ["closeQuestion", (d: AddendumOfficeDeps) => closeQuestion(QID, "out_of_scope", d), "close_question",
      { p_question_id: QID, p_reason: "out_of_scope" }],
  ] as const;

  for (const [name, run, rpc, args] of cases) {
    it(`${name} calls ${rpc}`, async () => {
      const d = deps();
      const r = await run(d);
      expect(r.ok).toBe(true);
      expect(d.call).toHaveBeenCalledWith(rpc, args);
    });
  }
});

describe("input checks before the database", () => {
  it("disagree, reopen and withdraw refuse a blank comment or reason without calling", async () => {
    for (const run of [
      (d: AddendumOfficeDeps) => disagree(AID, "   ", d),
      (d: AddendumOfficeDeps) => reopen(AID, "", d),
      (d: AddendumOfficeDeps) => withdraw(AID, " ", d),
    ]) {
      const d = deps();
      const r = await run(d);
      expect(r.ok).toBe(false);
      expect(d.call).not.toHaveBeenCalled();
    }
    const r = await disagree(AID, " ", deps());
    if (!r.ok) expect(r.message).toBe("Enter a comment.");
    const w = await withdraw(AID, " ", deps());
    if (!w.ok) expect(w.message).toBe("Enter a reason.");
  });

  it("returnAddendum needs at least one comment and text in every comment", async () => {
    for (const comments of [[], [{ field: null, body: "ok" }, { field: "narrative", body: "  " }]]) {
      const d = deps();
      const r = await returnAddendum(AID, comments, d);
      expect(r).toEqual({ ok: false, message: messageFor(new Error("invalid_comments")) });
      expect(d.call).not.toHaveBeenCalled();
    }
  });

  it("closeQuestion names the question, not an addendum, when it is not found", async () => {
    expect(await closeQuestion(QID, "duplicate", deps("not_found")))
      .toEqual({ ok: false, message: QUESTION_NOT_FOUND });
    expect(await closeQuestion("not-a-uuid", "duplicate", deps())).toEqual({ ok: false, message: QUESTION_NOT_FOUND });
    expect(QUESTION_NOT_FOUND).toBe("That question was not found. Reload the page.");
  });

  it("closeQuestion accepts only duplicate or out_of_scope", async () => {
    const d = deps();
    const r = await closeQuestion(QID, "rude" as never, d);
    expect(r).toEqual({ ok: false, message: "Choose why the question is closed." });
    expect(d.call).not.toHaveBeenCalled();
  });
});

describe("error mapping", () => {
  it("maps addendum-specific codes to addendum copy", async () => {
    expect((await sendToCheck(AID, deps("invalid_state")))).toEqual({
      ok: false, message: "This addendum is no longer in the right state for that action. Reload the page.",
    });
    expect(addendumMessageFor(new Error("not_found"))).toBe("That addendum was not found. Reload the page.");
    expect(addendumMessageFor(new Error("same_person")))
      .toBe("You reviewed this addendum in this round; a different person must check it.");
    expect(addendumMessageFor(new Error("question_in_addendum")))
      .toBe(messageFor(new Error("question_in_addendum")));
  });

  it("falls back to the shared office messages, then to the generic message", async () => {
    expect(await approveCheck(AID, deps("bids_closed"))).toEqual({ ok: false, message: messageFor(new Error("bids_closed")) });
    expect(await approveCheck(AID, deps("boom"))).toEqual({
      ok: false, message: "Something went wrong. Reload the page and try again.",
    });
  });
});

describe("withOffice (the server action wrapper)", () => {
  const ok = vi.fn(async () => ({ ok: true as const }));

  it("refuses a caller the guard rejects", async () => {
    const r = await withOffice(async () => { throw new Error("not_authorized"); }, AID, ok);
    expect(r).toEqual({ ok: false, message: "You are not allowed to do that." });
  });

  it("refuses a malformed id as not found", async () => {
    const r = await withOffice(async () => {}, "not-a-uuid", ok);
    expect(r).toEqual({ ok: false, message: "That addendum was not found. Reload the page." });
  });

  it("maps a thrown error and never rethrows", async () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    const r = await withOffice(async () => {}, AID, async () => { throw new Error("too_close"); });
    expect(r).toEqual({ ok: false, message: messageFor(new Error("too_close")) });
    spy.mockRestore();
  });

  it("passes the checked id through", async () => {
    const fn = vi.fn(async (i: string) => ({ ok: i === AID }));
    await withOffice(async () => {}, AID, fn);
    expect(fn).toHaveBeenCalledWith(AID);
  });
});

describe("publishWarning", () => {
  it("adds the answers-due sentence only when the answers-due date has passed", () => {
    expect(ANSWERS_DUE_PASSED).toBe("The answers-due date has passed. Publish anyway?");
    expect(publishWarning(2, false)).not.toContain(ANSWERS_DUE_PASSED);
    expect(publishWarning(2, true)).toContain(ANSWERS_DUE_PASSED);
    expect(publishWarning(2, true)).toContain("Addendum 2");
  });
});

describe("officeQuestionStatus", () => {
  it("names the addendum or the close reason", () => {
    expect(officeQuestionStatus({ status: "open", answeredInNumber: null, closeReason: null })).toBe("Open");
    expect(officeQuestionStatus({ status: "answered", answeredInNumber: 2, closeReason: null }))
      .toBe("Answered in Addendum 2");
    expect(officeQuestionStatus({ status: "closed", answeredInNumber: null, closeReason: "duplicate" }))
      .toBe("Closed: duplicate");
    expect(officeQuestionStatus({ status: "closed", answeredInNumber: null, closeReason: "out_of_scope" }))
      .toBe("Closed: out of scope");
  });
});

describe("addendumHistory", () => {
  const names = new Map([[USER, "Riley Office"]]);
  const fmt = (iso: string) => iso;

  it("labels the addendum actions and their notes", () => {
    const rows = addendumHistory([
      { id: 5, actor_id: USER, action: "publish_addendum", created_at: "t5",
        detail: { addendum_id: AID, version: 2, after_answers_due: true } },
      { id: 4, actor_id: USER, action: "approve_addendum_alone", created_at: "t4",
        detail: { addendum_id: AID, fallback: "no second reviewer available" } },
      { id: 3, actor_id: USER, action: "disagree_addendum", created_at: "t3", detail: { comment: "Name the sheet." } },
      { id: 2, actor_id: USER, action: "return_addendum", created_at: "t2",
        detail: { comments: [{ field: "narrative", body: "Say why." }, { field: null, body: "General" }] } },
      { id: 1, actor_id: null, action: "submit_addendum", created_at: "t1", detail: {} },
    ], names, fmt);
    expect(rows.map((r) => [r.action, r.actor, r.reason])).toEqual([
      ["Published", "Riley Office", "Published as version 2, after the answers-due date."],
      ["Approved alone (fallback)", "Riley Office",
        "Fallback: no second reviewer available. Recorded as a single-reviewer approval."],
      ["Checker disagreed", "Riley Office", "Comment: Name the sheet."],
      ["Returned to agency", "Riley Office", "narrative: Say why. | General"],
      ["Submitted", "Agency author", null],
    ]);
  });

  it("shows reasons and the new reviewer", () => {
    const rows = addendumHistory([
      { id: 2, actor_id: USER, action: "withdraw_addendum", created_at: "t", detail: { reason: "Superseded" } },
      { id: 1, actor_id: USER, action: "reassign_addendum_review", created_at: "t", detail: { new_reviewer_id: USER } },
    ], names, fmt);
    expect(rows.map((r) => r.reason)).toEqual(["Reason: Superseded", "New reviewer: Riley Office"]);
    expect(rows[0].action).toBe("Withdrawn");
  });
});
