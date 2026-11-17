import { describe, expect, it } from "vitest";
import { emptySolicitation } from "./schema";
import type { AttachmentKind, SolicitationData } from "./types";
import { validate, type IssueCode, type ValidationContext } from "./validate";

const ctx: ValidationContext = { tz: "America/Denver", holidays: [], submissionDate: "2026-07-29" };
const contact = (n: string) => ({ name: n, email: `${n}@example.test`, phone: "555-0100" });
const att = (kind: AttachmentKind) => ({ kind, label: kind, storagePath: `a/${kind}.pdf`, issueDate: null });

function validData(): SolicitationData {
  return {
    ...emptySolicitation(),
    shortTitle: "Roof Replacement", longTitle: "Roof Replacement at Calder Hall", category: "construction",
    summary: "Replace roof membranes", projectDescription: "Replace the roof on the main hall.",
    location: { address: "1 Example Way", city: "Calderton", county: "Calder" },
    requester: contact("requester"), projectManager: contact("pm"),
    estimateCents: 16_000_000, fundingSource: "capital_construction", federalFunds: false,
    releaseDate: "2026-08-03", adStart: "2026-08-03", adEnd: "2026-08-17", newspapers: "Calder Daily",
    questionsDue: { date: "2026-08-17", time: "13:00" },
    answersDue: { date: "2026-08-24", time: "13:00" },
    bidDueDate: "2026-08-31", bidDueTime: "13:00",
    schedule: { items: [{ name: "Base bid", description: "" }], alternates: [] },
    attachments: (["plans", "specifications", "sample_contract", "prevailing_wage"] as const).map(att),
  };
}
const without = (k: AttachmentKind) => validData().attachments.filter((a) => a.kind !== k);
const run = (over: Partial<SolicitationData>) => validate({ ...validData(), ...over }, ctx);
const has = (list: { code: IssueCode; field: string }[], code: IssueCode, field?: string) =>
  list.some((i) => i.code === code && (field === undefined || i.field === field));

function expectError(over: Partial<SolicitationData>, code: IssueCode, field: string) {
  const r = run(over);
  expect(has(r.errors, code, field), JSON.stringify(r)).toBe(true);
}
function expectWarning(over: Partial<SolicitationData>, code: IssueCode, field: string) {
  const r = run(over);
  expect(has(r.warnings, code, field), JSON.stringify(r)).toBe(true);
  expect(r.errors).toEqual([]);
}
function expectNoErrorCode(over: Partial<SolicitationData>, code: IssueCode) {
  expect(has(run(over).errors, code)).toBe(false);
}
function expectNoIssue(over: Partial<SolicitationData>) {
  expect(run(over)).toEqual({ errors: [], warnings: [] });
}

describe("validate", () => {
  it("accepts the valid fixture", () => {
    expect(validate(validData(), ctx)).toEqual({ errors: [], warnings: [] });
  });
  it("estimate below minimum", () => {
    expectError({ estimateCents: 4_999_999 }, "estimate_below_minimum", "estimateCents");
    expectNoErrorCode({ estimateCents: 5_000_000 }, "estimate_below_minimum");
  });
  it("short title length", () => {
    expectError({ shortTitle: "x".repeat(31) }, "short_title_too_long", "shortTitle");
    expectNoIssue({ shortTitle: "x".repeat(30) });
  });
  it("bid due too soon", () => {
    expectError({ bidDueDate: "2026-08-28" }, "bid_due_too_soon", "bidDueDate");
    expectNoErrorCode({ bidDueDate: "2026-08-29" }, "bid_due_too_soon");
  });
  it("release too soon", () => {
    expectError({ releaseDate: "2026-07-31" }, "release_too_soon", "releaseDate");
    expectNoErrorCode({ releaseDate: "2026-08-01" }, "release_too_soon");
  });
  it("ad period", () => {
    expectError({ adEnd: "2026-08-16" }, "ad_period_too_short", "adEnd");
    expectError({ adEnd: "2026-09-01" }, "ad_ends_after_bid_due", "adEnd");
  });
  it("date order", () => {
    expectError({ answersDue: { date: "2026-08-17", time: "12:00" } }, "date_order", "answersDue");
    expectError({ bidDueTime: "09:00", bidDueDate: "2026-08-24", answersDue: { date: "2026-08-24", time: "13:00" } }, "date_order", "bidDueDate");
  });
  it("release date must be before questions due (boundaries)", () => {
    // Fixture questions due 2026-08-17; adStart moved to the release date so the ad warning stays out of the way.
    const msg = "Release date must be before questions are due";
    const r = run({ releaseDate: "2026-08-18", adStart: "2026-08-18" });
    expect(r.errors.find((i) => i.code === "date_order" && i.field === "questionsDue")?.message).toBe(msg);
    expectError({ releaseDate: "2026-08-17", adStart: "2026-08-17" }, "date_order", "questionsDue");
    const dayBefore = run({ releaseDate: "2026-08-16", adStart: "2026-08-16" });
    expect(has(dayBefore.errors, "date_order", "questionsDue")).toBe(false);
  });
  it("ad start before release is an acknowledgeable warning (boundaries)", () => {
    expectWarning({ adStart: "2026-08-02" }, "ad_starts_before_release", "adStart");
    expectNoIssue({ adStart: "2026-08-03", adEnd: "2026-08-17" });
    expectNoIssue({ adStart: "2026-08-04", adEnd: "2026-08-18", bidDueDate: "2026-08-31" });
    const r = run({ adStart: "2026-08-02" });
    expect(r.errors).toEqual([]);
  });
  it("pre-bid completeness and window", () => {
    expectError({ preBid: { kind: "mandatory", format: "in_person", date: null, time: null, location: "" } }, "prebid_incomplete", "preBid.date");
    expectError({ preBid: { kind: "optional", format: "phone", date: "2026-08-18", time: "10:00", location: "x" } }, "prebid_out_of_window", "preBid.date");
    expectError({ preBid: { kind: "optional", format: "phone", date: "2026-08-03", time: "10:00", location: "x" } }, "prebid_out_of_window", "preBid.date");
    expectNoIssue({ preBid: { kind: "optional", format: "phone", date: "2026-08-12", time: "10:00", location: "x" } });
  });
  it("schedule", () => {
    expectError({ schedule: { items: [], alternates: [] } }, "schedule_empty", "schedule.items");
    expectError({ schedule: { items: [{ name: " ", description: "" }], alternates: [] } }, "required", "schedule.items.0.name");
  });
  it("attachments", () => {
    expectError({ estimateCents: 10_000_000, attachments: without("prevailing_wage") }, "attachment_missing", "attachments.prevailing_wage");
    expectNoIssue({ estimateCents: 9_999_999, attachments: without("prevailing_wage") });
    expectError({ attachments: without("plans") }, "attachment_missing", "attachments.plans");
  });
  it("warnings", () => {
    expectWarning({ bidDueDate: "2026-09-05" }, "bid_due_non_working_day", "bidDueDate");
    expectWarning({ preBid: { kind: "mandatory", format: "in_person", date: "2026-08-06", time: "10:00", location: "x" } }, "mandatory_prebid_soon", "preBid.date");
    expectWarning({ summary: "Replace [ROOF TYPE] membranes" }, "placeholder_text", "summary");
    const r = validate({ ...validData(), bidDueDate: "2026-09-07" }, { ...ctx, holidays: ["2026-09-07"] });
    expect(has(r.warnings, "bid_due_non_working_day", "bidDueDate")).toBe(true);
  });
  it("required", () => {
    expectError({ longTitle: "" }, "required", "longTitle");
    expectError({ estimateCents: null }, "required", "estimateCents");
    expectError({ requester: { ...contact("r"), email: "" } }, "required", "requester.email");
    expectError({ location: { address: "a", city: "", county: "c" } }, "required", "location.city");
    expectError({ fundingSource: "other", fundingOther: "" }, "required", "fundingOther");
    expectError({ backgroundCheck: { required: true, contact: "", leadDays: null } }, "required", "backgroundCheck.contact");
    expectError({ backgroundCheck: { required: true, contact: "x", leadDays: null } }, "required", "backgroundCheck.leadDays");
    expectNoIssue({ scopeNotes: "", specialProvisions: "", tentativeAwardDate: null });
  });
  it("reports at most one required issue per field and tolerates empty data", () => {
    const r = validate(emptySolicitation(), ctx);
    const fields = r.errors.filter((i) => i.code === "required").map((i) => i.field);
    expect(new Set(fields).size).toBe(fields.length);
    expect(fields).toContain("releaseDate");
    expect(has(r.errors, "schedule_empty")).toBe(true);
  });
});
