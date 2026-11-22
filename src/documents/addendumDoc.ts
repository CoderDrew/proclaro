import type { ScheduleChange } from "../domain/addendum/diff";
import type { SolicitationData } from "../domain/solicitation/types";
import type { LocalDate } from "../domain/time";
import { formatDate, formatDateTime, formatTimeWithZone, TBD } from "./format";

export interface DateChange { field: string; before: string; after: string }

/** Everything the addendum PDF prints. No question carries a name or an organization (spec §6). */
export interface AddendumDocContext {
  number: number;
  version: number;
  solicitationNumber: string;
  title: string;
  /** The publish date in settings.timezone. */
  publishedOn: LocalDate;
  narrative: string;
  changes: ScheduleChange[];
  dateChanges: DateChange[];
  answers: { publishedQuestion: string; answer: string }[];
}

const NO_PREBID = "No pre-bid meeting";

function bidDue(d: SolicitationData, tz: string): string {
  if (!d.bidDueDate) return TBD;
  return `${formatDate(d.bidDueDate)}, ${formatTimeWithZone(d.bidDueDate, d.bidDueTime, tz)}`;
}

function preBid(d: SolicitationData, tz: string): string {
  if (d.preBid.kind === "none") return NO_PREBID;
  return d.preBid.date && d.preBid.time ? formatDateTime({ date: d.preBid.date, time: d.preBid.time }, tz) : TBD;
}

/**
 * The key dates that differ between two versions' data, formatted as the RFB prints them (in `tz`). Compared on the
 * printed text, so a change that prints the same is not listed.
 */
export function dateChanges(before: SolicitationData, after: SolicitationData, tz: string): DateChange[] {
  const rows: [string, (d: SolicitationData) => string][] = [
    ["Questions due", (d) => formatDateTime(d.questionsDue, tz)],
    ["Answers issued by", (d) => formatDateTime(d.answersDue, tz)],
    ["Bids due", (d) => bidDue(d, tz)],
    ["Pre-bid meeting", (d) => preBid(d, tz)],
  ];
  return rows
    .map(([field, f]) => ({ field, before: f(before), after: f(after) }))
    .filter((c) => c.before !== c.after);
}
