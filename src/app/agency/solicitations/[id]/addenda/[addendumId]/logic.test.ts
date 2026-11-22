import { describe, expect, it, vi } from "vitest";
import { emptySolicitation } from "@/domain/solicitation/schema";
import type { SolicitationData } from "@/domain/solicitation/types";
import {
  addendumInProgress, addendumMessageFor, answerDraftProblems, canStartAddendum, narrativeProblems, parseAnswerInput,
  runAddendumCall, runStartAddendum, runSubmitAddendum, type AddendumSubmitDeps, type AnswerDraft,
} from "./logic";

const SID = "11111111-1111-4111-8111-111111111111";
const AID = "22222222-2222-4222-8222-222222222222";
const QID = "33333333-3333-4333-8333-333333333333";

/** Published data that passes every rule; bid due Tuesday 2027-02-02 13:00 Denver. */
function validData(over: Partial<SolicitationData> = {}): SolicitationData {
  return {
    ...emptySolicitation(),
    shortTitle: "Roof repair", longTitle: "Roof repair at the Calder Parks maintenance yard",
    category: "major_maintenance", summary: "Replace the roof.", projectDescription: "Replace the roof membrane.",
    location: { address: "1 Example Way", city: "Calder City", county: "Calder" },
    requester: { name: "Pat Example", email: "pat@example.test", phone: "555-0100" },
    projectManager: { name: "Sam Example", email: "sam@example.test", phone: "555-0101" },
    estimateCents: 15_000_000, fundingAmountCents: 15_000_000, fundingSource: "major_maintenance", federalFunds: false,
    releaseDate: "2027-01-12", adStart: "2027-01-12", adEnd: "2027-01-28", newspapers: "Calder Courier",
    questionsDue: { date: "2027-01-20", time: "13:00" }, answersDue: { date: "2027-01-22", time: "13:00" },
    bidDueDate: "2027-02-02",
    schedule: { items: [{ name: "Base bid", description: "" }], alternates: [] },
    attachments: [
      { kind: "plans", label: "Plans", storagePath: `solicitations/${SID}/a.pdf`, issueDate: "2027-01-01" },
      { kind: "specifications", label: "Specs", storagePath: `solicitations/${SID}/b.pdf`, issueDate: "2027-01-01" },
      { kind: "sample_contract", label: "Contract", storagePath: `solicitations/${SID}/c.pdf`, issueDate: null },
      { kind: "prevailing_wage", label: "Wages", storagePath: `solicitations/${SID}/d.pdf`, issueDate: null },
    ],
    ...over,
  };
}

function deps(over: Partial<AddendumSubmitDeps> = {}, row: Partial<Awaited<ReturnType<AddendumSubmitDeps["loadAddendum"]>>> = {}) {
  return {
    loadAddendum: vi.fn(async () => ({
      state: "draft", data: validData(), narrative: "Moves the bid due date.", baseData: validData(), ...row,
    })),
    validationContext: vi.fn(async () => ({
      tz: "America/Denver", holidays: [], submissionDate: "2027-01-10", mode: "addendum" as const,
      now: new Date("2027-01-10T17:00:00Z"),
    })),
    submit: vi.fn(async () => {}),
    ...over,
  };
}

describe("canStartAddendum", () => {
  it("is true only for a published solicitation still open with nothing in progress", () => {
    expect(canStartAddendum("published", false, false)).toBe(true);
    expect(canStartAddendum("published", true, false)).toBe(false);
    expect(canStartAddendum("published", false, true)).toBe(false);
    expect(canStartAddendum("approved", false, false)).toBe(false);
    expect(canStartAddendum("draft", false, false)).toBe(false);
  });
});

describe("addendumInProgress", () => {
  it("counts any addendum whose effective state is neither published nor withdrawn", () => {
    expect(addendumInProgress([])).toBe(false);
    expect(addendumInProgress([{ effective_state: "published" }, { effective_state: "withdrawn" }])).toBe(false);
    for (const s of ["draft", "submitted", "in_review", "in_check", "approved"]) {
      expect(addendumInProgress([{ effective_state: "published" }, { effective_state: s }])).toBe(true);
    }
  });
});

describe("answerDraftProblems", () => {
  const a = (over: Partial<AnswerDraft> = {}): AnswerDraft => ({
    questionId: QID, label: "Question 1", publishedQuestion: "Is there a site visit?", answer: "No.", saved: true, ...over,
  });

  it("is empty for saved, complete answers", () => {
    expect(answerDraftProblems([a()])).toEqual([]);
    expect(answerDraftProblems([])).toEqual([]);
  });

  it("flags a blank published question or answer, per question", () => {
    const p = answerDraftProblems([a({ publishedQuestion: "  " }), a({ questionId: "q2", label: "Question 2", answer: "" })]);
    expect(p).toEqual([
      expect.objectContaining({ code: "required", field: `answers.${QID}.publishedQuestion` }),
      expect.objectContaining({ code: "required", field: "answers.q2.answer" }),
    ]);
    expect(p[0].message).toContain("Question 1");
    expect(p[1].message).toContain("Question 2");
  });

  it("flags an answer that was opened or edited but not saved", () => {
    const p = answerDraftProblems([a({ saved: false })]);
    expect(p).toEqual([expect.objectContaining({ code: "required", field: `answers.${QID}` })]);
    expect(p[0].message).toMatch(/save or remove/i);
  });
});

describe("narrativeProblems", () => {
  it("requires a non-blank narrative", () => {
    expect(narrativeProblems("Moves the bid due date.")).toEqual([]);
    expect(narrativeProblems("   ")).toEqual([expect.objectContaining({ code: "required", field: "narrative" })]);
  });
});

describe("parseAnswerInput", () => {
  it("trims and accepts 1 to 4,000 characters for both fields", () => {
    expect(parseAnswerInput("  Q?  ", " A. ")).toEqual({ ok: true, value: { publishedQuestion: "Q?", answer: "A." } });
  });
  it("refuses blank or over-long text", () => {
    expect(parseAnswerInput("", "A.").ok).toBe(false);
    expect(parseAnswerInput("Q?", " ").ok).toBe(false);
    expect(parseAnswerInput("x".repeat(4001), "A.").ok).toBe(false);
    expect(parseAnswerInput(42 as unknown as string, "A.").ok).toBe(false);
  });
});

describe("addendumMessageFor", () => {
  it("maps every database code the addendum functions raise to plain copy", () => {
    const codes = [
      "addendum_in_progress", "locked_field", "narrative_required", "invalid_data", "bids_closed", "invalid_state",
      "not_authorized", "reason_required", "not_found", "question_not_open", "not_open", "invalid_attachment_path",
    ];
    const generic = addendumMessageFor(new Error("something_else"));
    for (const c of codes) {
      const m = addendumMessageFor(new Error(c));
      expect(m, c).not.toBe(generic);
      expect(m, c).not.toContain("_");
    }
    expect(addendumMessageFor(new Error("addendum_in_progress"))).toMatch(/already in progress/i);
    expect(addendumMessageFor(new Error("bids_closed"))).toMatch(/closed/i);
  });
  it("falls back to generic copy for unknown errors and non-errors", () => {
    expect(addendumMessageFor(null)).toMatch(/something went wrong/i);
    expect(addendumMessageFor("bids_closed")).toMatch(/something went wrong/i);
  });
});

describe("runAddendumCall", () => {
  it("returns ok when the call resolves", async () => {
    expect(await runAddendumCall(async () => {})).toEqual({ ok: true });
  });
  it("maps a thrown database code to its message", async () => {
    const r = await runAddendumCall(async () => { throw new Error("locked_field"); });
    expect(r).toEqual({ ok: false, message: addendumMessageFor(new Error("locked_field")) });
  });
});

describe("runStartAddendum", () => {
  it("returns the new id", async () => {
    const start = vi.fn(async () => AID);
    expect(await runStartAddendum(SID, { start })).toEqual({ ok: true, id: AID });
    expect(start).toHaveBeenCalledWith(SID);
  });
  it("maps addendum_in_progress and bids_closed", async () => {
    for (const code of ["addendum_in_progress", "bids_closed"]) {
      const r = await runStartAddendum(SID, { start: async () => { throw new Error(code); } });
      expect(r).toEqual({ ok: false, message: addendumMessageFor(new Error(code)) });
    }
  });
  it("refuses a malformed id without calling the database", async () => {
    const start = vi.fn(async () => AID);
    expect((await runStartAddendum("nope", { start })).ok).toBe(false);
    expect(start).not.toHaveBeenCalled();
  });
});

describe("runSubmitAddendum", () => {
  it("submits a clean draft", async () => {
    const d = deps();
    expect(await runSubmitAddendum(AID, d)).toEqual({ ok: true });
    expect(d.submit).toHaveBeenCalledWith(AID);
  });

  it("validates in addendum mode: locked-field rules are skipped, the 5-day rule applies", async () => {
    // Release date in the past would fail setup mode; addendum mode skips it.
    const ok = deps({}, { data: validData({ releaseDate: "2026-12-01", adStart: "2026-12-01" }),
      baseData: validData({ releaseDate: "2026-12-01", adStart: "2026-12-01" }) });
    expect(await runSubmitAddendum(AID, ok)).toEqual({ ok: true });

    const close = deps({ validationContext: async () => ({
      tz: "America/Denver", holidays: [], submissionDate: "2027-01-30", mode: "addendum" as const,
      now: new Date("2027-01-30T17:00:00Z"),
    }) });
    const r = await runSubmitAddendum(AID, close);
    expect(r.ok).toBe(false);
    if (!r.ok && "errors" in r) expect(r.errors.map((e) => e.code)).toContain("too_close");
    expect(close.submit).not.toHaveBeenCalled();
  });

  it("refuses a blank narrative before calling the database", async () => {
    const d = deps({}, { narrative: " " });
    const r = await runSubmitAddendum(AID, d);
    expect(r.ok).toBe(false);
    if (!r.ok && "errors" in r) expect(r.errors).toEqual([expect.objectContaining({ field: "narrative" })]);
    expect(d.submit).not.toHaveBeenCalled();
  });

  it("refuses a changed locked field", async () => {
    const d = deps({}, { data: validData({ newspapers: "Other Paper" }) });
    const r = await runSubmitAddendum(AID, d);
    expect(r.ok).toBe(false);
    if (!r.ok && "errors" in r) {
      expect(r.errors).toEqual([expect.objectContaining({ code: "locked_field", field: "newspapers" })]);
    }
    expect(d.submit).not.toHaveBeenCalled();
  });

  it("does not block on warnings (addenda have no warning acknowledgments)", async () => {
    // 2027-02-06 is a Saturday: a non-working-day warning only.
    const d = deps({}, { data: validData({ bidDueDate: "2027-02-06" }) });
    expect(await runSubmitAddendum(AID, d)).toEqual({ ok: true });
  });

  it("returns a message for a missing or non-draft addendum", async () => {
    const missing = deps({ loadAddendum: async () => null });
    expect(await runSubmitAddendum(AID, missing)).toEqual({ ok: false, message: addendumMessageFor(new Error("not_found")) });
    const sent = deps({}, { state: "submitted" });
    expect(await runSubmitAddendum(AID, sent)).toEqual({ ok: false, message: addendumMessageFor(new Error("invalid_state")) });
  });

  it("maps database refusals from submit_addendum", async () => {
    for (const code of ["bids_closed", "narrative_required", "not_authorized"]) {
      const d = deps({ submit: async () => { throw new Error(code); } });
      expect(await runSubmitAddendum(AID, d)).toEqual({ ok: false, message: addendumMessageFor(new Error(code)) });
    }
  });
});
