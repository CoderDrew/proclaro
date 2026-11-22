import { LOCKED_FIELDS } from "../addendum/lockedFields";
import { diffDays, isNonWorkingDay, toUtc, type LocalDate } from "../time";
import type { AttachmentKind, SolicitationData } from "./types";
import { BLOCKED_BELOW, PREVAILING_WAGE_AT } from "./valueBands";

export type IssueCode =
  | "required" | "short_title_too_long" | "estimate_below_minimum" | "schedule_empty"
  | "date_order" | "bid_due_too_soon" | "release_too_soon" | "ad_period_too_short" | "ad_ends_after_bid_due"
  | "prebid_incomplete" | "prebid_out_of_window" | "attachment_missing"
  | "bid_due_non_working_day" | "mandatory_prebid_soon" | "placeholder_text" | "ad_starts_before_release"
  | "funding_below_estimate" | "too_close" | "locked_field";

/** `field` is a dotted path, e.g. "preBid.date". */
export interface Issue { code: IssueCode; field: string; message: string }
interface BaseContext { tz: string; holidays: LocalDate[]; submissionDate: LocalDate }
/**
 * `setup` (the default) validates a solicitation before it is published. `addendum` validates an addendum's data:
 * locked fields and the release-vs-submission rule are skipped, and bids must stay open 5 days past `now`.
 */
export type ValidationContext = BaseContext & ({ mode?: "setup" } | { mode: "addendum"; now: Date });
export interface ValidationResult { errors: Issue[]; warnings: Issue[] }

type Rule = (d: SolicitationData, ctx: ValidationContext) => Issue[];

const WARNING_CODES: ReadonlySet<IssueCode> = new Set<IssueCode>([
  "bid_due_non_working_day", "mandatory_prebid_soon", "placeholder_text", "ad_starts_before_release",
  "funding_below_estimate",
]);

const SHORT_TITLE_MAX = 30;
const MIN_ANSWERS_TO_BID_DAYS = 5;
const MIN_SUBMISSION_TO_RELEASE_DAYS = 3;
const MIN_AD_DAYS = 14;
const MANDATORY_PREBID_MIN_LEAD_DAYS = 7;
const ADDENDUM_MIN_OPEN_MS = 5 * 24 * 60 * 60 * 1000;

const issue = (code: IssueCode, field: string, message: string): Issue => ({ code, field, message });
const blank = (v: unknown): boolean =>
  v === null || v === undefined || (typeof v === "string" && v.trim() === "") ||
  (typeof v === "number" && !Number.isFinite(v));

const requiredRule: Rule = (d) => {
  const out: Issue[] = [];
  const need = (field: string, value: unknown) => {
    if (blank(value)) out.push(issue("required", field, "This field is required."));
  };
  need("shortTitle", d.shortTitle);
  need("longTitle", d.longTitle);
  need("category", d.category);
  need("summary", d.summary);
  need("projectDescription", d.projectDescription);
  need("location.address", d.location.address);
  need("location.city", d.location.city);
  need("location.county", d.location.county);
  for (const who of ["requester", "projectManager"] as const) {
    need(`${who}.name`, d[who].name);
    need(`${who}.email`, d[who].email);
    need(`${who}.phone`, d[who].phone);
  }
  need("estimateCents", d.estimateCents);
  need("fundingAmountCents", d.fundingAmountCents);
  need("fundingSource", d.fundingSource);
  if (d.fundingSource === "other") need("fundingOther", d.fundingOther);
  need("federalFunds", d.federalFunds);
  need("releaseDate", d.releaseDate);
  need("adStart", d.adStart);
  need("adEnd", d.adEnd);
  need("newspapers", d.newspapers);
  need("questionsDue", d.questionsDue);
  need("answersDue", d.answersDue);
  need("bidDueDate", d.bidDueDate);
  need("bidDueTime", d.bidDueTime);
  need("bidValidityDays", d.bidValidityDays);
  if (d.backgroundCheck.required) {
    need("backgroundCheck.contact", d.backgroundCheck.contact);
    need("backgroundCheck.leadDays", d.backgroundCheck.leadDays);
  }
  d.schedule.items.forEach((it, i) => need(`schedule.items.${i}.name`, it.name));
  return out;
};

const shortTitleRule: Rule = (d) =>
  d.shortTitle.length > SHORT_TITLE_MAX
    ? [issue("short_title_too_long", "shortTitle", `Short title must be ${SHORT_TITLE_MAX} characters or fewer.`)]
    : [];

const estimateRule: Rule = (d) =>
  d.estimateCents !== null && d.estimateCents < BLOCKED_BELOW
    ? [issue("estimate_below_minimum", "estimateCents", "Estimate must be at least $50,000.00.")]
    : [];

/** Funding below the estimate is allowed (the agency may add funds or rely on deductive alternates), so a warning. */
const fundingRule: Rule = (d) =>
  d.estimateCents !== null && d.fundingAmountCents !== null && d.fundingAmountCents < d.estimateCents
    ? [issue("funding_below_estimate", "fundingAmountCents", "Funding amount is below the estimate.")]
    : [];

const scheduleRule: Rule = (d) =>
  d.schedule.items.length === 0
    ? [issue("schedule_empty", "schedule.items", "Add at least one bid schedule line item.")]
    : [];

const dateOrderRule: Rule = (d, ctx) => {
  const out: Issue[] = [];
  const { questionsDue: q, answersDue: a } = d;
  // Calendar-day comparison: the release is a whole day, so questions due on the release date are too early.
  if (d.releaseDate && q && d.releaseDate >= q.date) {
    out.push(issue("date_order", "questionsDue", "Release date must be before questions are due"));
  }
  if (q && a && toUtc(q.date, q.time, ctx.tz) >= toUtc(a.date, a.time, ctx.tz)) {
    out.push(issue("date_order", "answersDue", "Answers due must be after questions due."));
  }
  if (a && d.bidDueDate && d.bidDueTime &&
      toUtc(a.date, a.time, ctx.tz) >= toUtc(d.bidDueDate, d.bidDueTime, ctx.tz)) {
    out.push(issue("date_order", "bidDueDate", "Bid due must be after answers due."));
  }
  return out;
};

const bidDueGapRule: Rule = (d) =>
  d.answersDue && d.bidDueDate && diffDays(d.bidDueDate, d.answersDue.date) < MIN_ANSWERS_TO_BID_DAYS
    ? [issue("bid_due_too_soon", "bidDueDate", `Bid due must be at least ${MIN_ANSWERS_TO_BID_DAYS} days after answers due.`)]
    : [];

const releaseRule: Rule = (d, ctx) =>
  d.releaseDate && diffDays(d.releaseDate, ctx.submissionDate) < MIN_SUBMISSION_TO_RELEASE_DAYS
    ? [issue("release_too_soon", "releaseDate", `Release must be at least ${MIN_SUBMISSION_TO_RELEASE_DAYS} days after submission.`)]
    : [];

const adRule: Rule = (d) => {
  const out: Issue[] = [];
  if (d.adStart && d.adEnd && diffDays(d.adEnd, d.adStart) < MIN_AD_DAYS) {
    out.push(issue("ad_period_too_short", "adEnd", `Advertisement period must be at least ${MIN_AD_DAYS} days.`));
  }
  if (d.adEnd && d.bidDueDate && d.adEnd > d.bidDueDate) {
    out.push(issue("ad_ends_after_bid_due", "adEnd", "Advertisement must end on or before the bid due date."));
  }
  return out;
};

/** Advertising may legitimately start before the posting, so this is a warning, not an error (Ruling 14). */
const adBeforeReleaseRule: Rule = (d) =>
  d.adStart && d.releaseDate && d.adStart < d.releaseDate
    ? [issue("ad_starts_before_release", "adStart", "Advertisement starts before the release date.")]
    : [];

const preBidRule: Rule = (d, ctx) => {
  const p = d.preBid;
  if (p.kind === "none") return [];
  const out: Issue[] = [];
  const need = (field: string, value: unknown) => {
    if (blank(value)) out.push(issue("prebid_incomplete", `preBid.${field}`, `Pre-bid meeting ${field} is required.`));
  };
  need("format", p.format);
  need("date", p.date);
  need("time", p.time);
  need("location", p.location);
  if (p.date) {
    const afterRelease = d.releaseDate ? p.date > d.releaseDate : true;
    const beforeQuestions = d.questionsDue
      ? toUtc(p.date, p.time ?? "00:00", ctx.tz) < toUtc(d.questionsDue.date, d.questionsDue.time, ctx.tz)
      : true;
    if (!afterRelease || !beforeQuestions) {
      out.push(issue("prebid_out_of_window", "preBid.date", "Pre-bid meeting must be after the release date and before questions are due."));
    }
  }
  return out;
};

const attachmentRule: Rule = (d) => {
  const needed: AttachmentKind[] = ["plans", "specifications", "sample_contract"];
  if (d.estimateCents !== null && d.estimateCents >= PREVAILING_WAGE_AT) needed.push("prevailing_wage");
  return needed
    .filter((k) => !d.attachments.some((a) => a.kind === k))
    .map((k) => issue("attachment_missing", `attachments.${k}`, `A ${k.replace(/_/g, " ")} attachment is required.`));
};

const nonWorkingRule: Rule = (d, ctx) =>
  d.bidDueDate && isNonWorkingDay(d.bidDueDate, ctx.holidays)
    ? [issue("bid_due_non_working_day", "bidDueDate", "Bid due date falls on a weekend or holiday.")]
    : [];

const mandatoryPreBidRule: Rule = (d) =>
  d.preBid.kind === "mandatory" && d.preBid.date && d.releaseDate &&
  diffDays(d.preBid.date, d.releaseDate) < MANDATORY_PREBID_MIN_LEAD_DAYS
    ? [issue("mandatory_prebid_soon", "preBid.date", `Mandatory pre-bid meeting is less than ${MANDATORY_PREBID_MIN_LEAD_DAYS} days after release.`)]
    : [];

const placeholderRule: Rule = (d) =>
  (["summary", "projectDescription", "scopeNotes", "specialProvisions"] as const)
    .filter((f) => /[[\]]/.test(d[f]))
    .map((f) => issue("placeholder_text", f, "This text still contains template placeholder brackets."));

const RULES: Rule[] = [
  requiredRule, shortTitleRule, estimateRule, fundingRule, scheduleRule, dateOrderRule, bidDueGapRule,
  releaseRule, adRule, adBeforeReleaseRule, preBidRule, attachmentRule, nonWorkingRule, mandatoryPreBidRule, placeholderRule,
];

/** Addendum mode: the bid due instant must be at least 5 days after publish (judged here against ctx.now). */
const tooCloseRule: Rule = (d, ctx) =>
  ctx.mode === "addendum" && d.bidDueDate && d.bidDueTime &&
  toUtc(d.bidDueDate, d.bidDueTime, ctx.tz).getTime() < ctx.now.getTime() + ADDENDUM_MIN_OPEN_MS
    ? [issue("too_close", "bidDueDate", "Bids must stay open at least 5 days after this addendum is published.")]
    : [];

const LOCKED: ReadonlySet<string> = new Set(LOCKED_FIELDS);
const isLocked = (i: Issue) => LOCKED.has(i.field.split(".")[0]);

export function validate(data: SolicitationData, ctx: ValidationContext): ValidationResult {
  const all = ctx.mode === "addendum"
    ? [...RULES.filter((r) => r !== releaseRule), tooCloseRule].flatMap((rule) => rule(data, ctx)).filter((i) => !isLocked(i))
    : RULES.flatMap((rule) => rule(data, ctx));
  return {
    errors: all.filter((i) => !WARNING_CODES.has(i.code)),
    warnings: all.filter((i) => WARNING_CODES.has(i.code)),
  };
}
