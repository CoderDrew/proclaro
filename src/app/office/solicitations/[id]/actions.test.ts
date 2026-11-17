import { describe, expect, it, vi } from "vitest";
import { emptySolicitation } from "@/domain/solicitation/schema";
import type { SolicitationData } from "@/domain/solicitation/types";
import {
  approveAlone, approveCheck, disagree, editAsReviewer, reopenReview, returnToAgency, sendToCheck,
  type OfficeDeps,
} from "./logic";

const ID = "11111111-1111-4111-8111-111111111111";

function validData(over: Partial<SolicitationData> = {}): SolicitationData {
  return {
    ...emptySolicitation(),
    shortTitle: "Roof repair", longTitle: "Roof repair at the Calder Parks maintenance yard",
    category: "major_maintenance", summary: "Replace the roof.", projectDescription: "Replace the roof membrane.",
    location: { address: "1 Example Way", city: "Calder City", county: "Calder" },
    requester: { name: "Pat Example", email: "pat@example.test", phone: "555-0100" },
    projectManager: { name: "Sam Example", email: "sam@example.test", phone: "555-0101" },
    estimateCents: 15_000_000, fundingSource: "major_maintenance", federalFunds: false,
    releaseDate: "2027-01-12", adStart: "2027-01-12", adEnd: "2027-01-28", newspapers: "Calder Courier",
    questionsDue: { date: "2027-01-20", time: "13:00" }, answersDue: { date: "2027-01-22", time: "13:00" },
    bidDueDate: "2027-02-02",
    schedule: { items: [{ name: "Base bid", description: "" }], alternates: [] },
    attachments: [
      { kind: "plans", label: "Plans", storagePath: `solicitations/${ID}/a.pdf`, issueDate: "2027-01-01" },
      { kind: "specifications", label: "Specs", storagePath: `solicitations/${ID}/b.pdf`, issueDate: "2027-01-01" },
      { kind: "sample_contract", label: "Contract", storagePath: `solicitations/${ID}/c.pdf`, issueDate: null },
      { kind: "prevailing_wage", label: "Wages", storagePath: `solicitations/${ID}/d.pdf`, issueDate: null },
    ],
    ...over,
  };
}

// Submitted 2027-01-09 10:00 Denver (17:00 UTC): release 2027-01-12 is exactly 3 days later.
const SUBMITTED_AT = "2027-01-09T17:00:00+00:00";

// "Today" for the gate: 2027-01-10 in Denver, before the fixture's 2027-01-12 release date.
const NOW = new Date("2027-01-10T17:00:00Z");

function deps(data: SolicitationData, over: Partial<OfficeDeps> = {}, state = "in_review") {
  return {
    now: () => NOW,
    call: vi.fn(async () => {}),
    loadRow: vi.fn(async () => ({ data, state, latestSubmittedAt: SUBMITTED_AT as string | null })),
    settings: vi.fn(async () => ({ tz: "America/Denver", holidays: [] as string[] })),
    loadAcks: vi.fn(async () => [] as { code: string; field: string | null }[]),
    ...over,
  } satisfies OfficeDeps;
}

describe("sendToCheck / approveAlone gate", () => {
  for (const [name, fn, rpc] of [
    ["sendToCheck", sendToCheck, "send_to_check"],
    ["approveAlone", approveAlone, "approve_alone"],
  ] as const) {
    it(`${name} refuses with errors when validation has errors`, async () => {
      const d = deps(validData({ shortTitle: "" }));
      const r = await fn(ID, d);
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.errors?.map((e) => e.field)).toContain("shortTitle");
      expect(d.call).not.toHaveBeenCalled();
    });

    it(`${name} refuses on unacknowledged warnings, accepts once acknowledged`, async () => {
      const data = validData({ bidDueDate: "2027-02-06" }); // a Saturday
      const d = deps(data);
      const r = await fn(ID, d);
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.unacknowledged).toEqual([expect.objectContaining({ code: "bid_due_non_working_day", field: "bidDueDate" })]);
      expect(d.call).not.toHaveBeenCalled();

      const d2 = deps(data, { loadAcks: vi.fn(async () => [{ code: "bid_due_non_working_day", field: "bidDueDate" }]) });
      expect(await fn(ID, d2)).toEqual({ ok: true });
      expect(d2.call).toHaveBeenCalledWith(rpc, { p_id: ID });
    });

    it(`${name} measures the 3-day rule from the latest submission, not today`, async () => {
      // Release 2027-01-12 passes when submitted 01-09 (3 days) but fails when resubmitted 01-11.
      const d = deps(validData(), {
        loadRow: vi.fn(async () => ({
          data: validData(), state: "in_review", latestSubmittedAt: "2027-01-11T17:00:00+00:00",
        })),
      });
      const r = await fn(ID, d);
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.errors?.map((e) => e.code)).toContain("release_too_soon");
      expect(d.call).not.toHaveBeenCalled();
      expect(await fn(ID, deps(validData()))).toEqual({ ok: true });
    });

    it(`${name} refuses a release date that has passed today, with publish's code and message`, async () => {
      // Release 2027-01-12: today 01-12 (Denver) is allowed, 01-13 is refused, measured in the configured zone.
      const at = (iso: string) => deps(validData(), { now: () => new Date(iso) });
      expect(await fn(ID, at("2027-01-12T17:00:00Z"))).toEqual({ ok: true });
      // 2027-01-13T05:00Z is still 01-12 in Denver (UTC-7): not passed.
      expect(await fn(ID, at("2027-01-13T05:00:00Z"))).toEqual({ ok: true });
      const late = at("2027-01-13T17:00:00Z");
      const r = await fn(ID, late);
      expect(r.ok).toBe(false);
      if (!r.ok) {
        expect(r.errors?.[0]).toEqual({
          code: "release_too_soon", field: "releaseDate",
          message: "Release date has passed; correct the dates before publishing",
        });
      }
      expect(late.call).not.toHaveBeenCalled();
    });

    it(`${name} returns a message instead of throwing when the state is wrong`, async () => {
      const r = await fn(ID, deps(validData(), {}, "in_check"));
      expect(r).toEqual({ ok: false, message: expect.stringMatching(/no longer/i) });
    });

    it(`${name} maps database errors to messages`, async () => {
      const d = deps(validData(), { call: vi.fn(async () => { throw new Error("not_authorized"); }) });
      const r = await fn(ID, d);
      expect(r).toEqual({ ok: false, message: expect.stringMatching(/not allowed/i) });
    });
  }
});

describe("reopenReview", () => {
  it("requires a reason before calling the database", async () => {
    const d = deps(validData(), {}, "approved");
    expect(await reopenReview(ID, "   ", d)).toEqual({ ok: false, message: "Enter a reason for the change." });
    expect(d.call).not.toHaveBeenCalled();
  });

  it("calls reopen_review with the trimmed reason", async () => {
    const d = deps(validData(), {}, "approved");
    expect(await reopenReview(ID, "  Release date passed  ", d)).toEqual({ ok: true });
    expect(d.call).toHaveBeenCalledWith("reopen_review", { p_id: ID, p_reason: "Release date passed" });
  });

  it("maps database errors to typed messages", async () => {
    const d = deps(validData(), { call: vi.fn(async () => { throw new Error("not_authorized"); }) }, "approved");
    expect(await reopenReview(ID, "why", d)).toEqual({ ok: false, message: expect.stringMatching(/not allowed/i) });
  });
});

describe("approveCheck / disagree", () => {
  it("approveCheck maps same_person to the reviewer message", async () => {
    const d = deps(validData(), { call: vi.fn(async () => { throw new Error("same_person"); }) }, "in_check");
    expect(await approveCheck(ID, d)).toEqual({
      ok: false,
      message: "You reviewed this solicitation; a different person must check it.",
    });
  });

  it("approveCheck maps invalid_state", async () => {
    const d = deps(validData(), { call: vi.fn(async () => { throw new Error("invalid_state"); }) });
    const r = await approveCheck(ID, d);
    expect(r.ok).toBe(false);
  });

  it("disagree sends null, not '', for an empty field, and refuses a blank comment up front", async () => {
    const d = deps(validData(), {}, "in_check");
    expect(await disagree(ID, "Fix the dates", "", d)).toEqual({ ok: true });
    expect(d.call).toHaveBeenCalledWith("disagree", { p_id: ID, p_comment: "Fix the dates", p_field: null });
    const d2 = deps(validData());
    expect(await disagree(ID, "   ", null, d2)).toEqual({ ok: false, message: expect.stringMatching(/comment/i) });
    expect(d2.call).not.toHaveBeenCalled();
  });
});

describe("editAsReviewer", () => {
  it("refuses a blank reason before calling the database", async () => {
    const d = deps(validData());
    const r = await editAsReviewer(ID, validData(), "   ", d);
    expect(r).toEqual({ ok: false, message: expect.stringMatching(/reason/i) });
    expect(d.call).not.toHaveBeenCalled();
    expect(d.loadRow).not.toHaveBeenCalled();
  });

  it("sends the full Zod-parsed data object, not a patch", async () => {
    const d = deps(validData());
    const edited = { ...validData(), bidDueDate: "2027-02-03", junk: "stripped" };
    expect(await editAsReviewer(ID, edited, " Corrected the date ", d)).toEqual({ ok: true });
    expect(d.call).toHaveBeenCalledTimes(1);
    const [fn, args] = vi.mocked(d.call).mock.calls[0] as unknown as [string, { p_data: Record<string, unknown>; p_reason: string }];
    expect(fn).toBe("office_update_data");
    expect(args.p_reason).toBe("Corrected the date");
    expect(args.p_data.bidDueDate).toBe("2027-02-03");
    expect(args.p_data.shortTitle).toBe("Roof repair");
    expect(Object.keys(args.p_data).sort()).toEqual(Object.keys(validData()).sort());
  });

  it("refuses invalid data and attachments outside the solicitation's folder", async () => {
    const d = deps(validData());
    expect((await editAsReviewer(ID, { shortTitle: 5 }, "x", d)).ok).toBe(false);
    const bad = validData({ attachments: [{ kind: "plans", label: "P", storagePath: "solicitations/other/a.pdf", issueDate: null }] });
    expect((await editAsReviewer(ID, bad, "x", d)).ok).toBe(false);
    expect(d.call).not.toHaveBeenCalled();
  });

  it("maps reason_required from the database", async () => {
    const d = deps(validData(), { call: vi.fn(async () => { throw new Error("reason_required"); }) });
    expect((await editAsReviewer(ID, validData(), "because", d)).ok).toBe(false);
  });
});

describe("returnToAgency", () => {
  it("requires at least one comment with text, and passes null for a general comment", async () => {
    const d = deps(validData());
    expect((await returnToAgency(ID, [], d)).ok).toBe(false);
    expect((await returnToAgency(ID, [{ field: null, body: "  " }], d)).ok).toBe(false);
    expect(d.call).not.toHaveBeenCalled();

    expect(await returnToAgency(ID, [{ field: "", body: " General " }, { field: "bidDueDate", body: "Too early" }], d)).toEqual({ ok: true });
    expect(d.call).toHaveBeenCalledWith("return_to_agency", {
      p_id: ID,
      p_comments: [{ field: null, body: "General" }, { field: "bidDueDate", body: "Too early" }],
    });
  });
});
