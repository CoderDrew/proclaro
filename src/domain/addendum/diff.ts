import type { SolicitationData } from "../solicitation/types";

type Schedule = SolicitationData["schedule"];
type Item = Schedule["items"][number];
type Alternate = Schedule["alternates"][number];

/** One positional difference between two bid schedules. `position` is 1-based. */
export type ScheduleChange = {
  kind: "item" | "alternate";
  change: "added" | "removed" | "changed";
  position: number;
  before?: string;
  after?: string;
};

function itemLabel(i: Item): string {
  return i.description ? `${i.name}: ${i.description}` : i.name;
}

function alternateLabel(a: Alternate): string {
  const kind = a.kind === "additive" ? "Additive" : "Deductive";
  return a.description ? `${kind}: ${a.description}` : kind;
}

function sameItem(a: Item, b: Item): boolean {
  return a.name === b.name && a.description === b.description;
}

function sameAlternate(a: Alternate, b: Alternate): boolean {
  return a.kind === b.kind && a.description === b.description;
}

function diffList<T>(
  kind: ScheduleChange["kind"], before: T[], after: T[], same: (a: T, b: T) => boolean, label: (x: T) => string,
): ScheduleChange[] {
  const changes: ScheduleChange[] = [];
  for (let i = 0; i < Math.max(before.length, after.length); i++) {
    const position = i + 1;
    if (i >= before.length) changes.push({ kind, change: "added", position, after: label(after[i]) });
    else if (i >= after.length) changes.push({ kind, change: "removed", position, before: label(before[i]) });
    else if (!same(before[i], after[i])) {
      changes.push({ kind, change: "changed", position, before: label(before[i]), after: label(after[i]) });
    }
  }
  return changes;
}

/**
 * The positional diff between two bid schedules: items first, then alternates, each in position order. Items have no
 * ids, so a reorder shows as changes at each moved position. app.schedule_changed (0029) is the SQL twin of
 * scheduleChanged; diff.test.ts and addendum_publish.test.sql pin the same six cases.
 */
export function diffSchedule(oldSchedule: Schedule, newSchedule: Schedule): ScheduleChange[] {
  return [
    ...diffList("item", oldSchedule.items, newSchedule.items, sameItem, itemLabel),
    ...diffList("alternate", oldSchedule.alternates, newSchedule.alternates, sameAlternate, alternateLabel),
  ];
}

/** True when the schedule differs in count, order, name, description or kind (spec §4). */
export function scheduleChanged(oldSchedule: Schedule, newSchedule: Schedule): boolean {
  return diffSchedule(oldSchedule, newSchedule).length > 0;
}

/**
 * The one sentence for a schedule change, shared by the agency editor, the office review page and the addendum PDF,
 * e.g. `Item 3 added: Paving`, `Alternate 1 removed: …`, `Item 2 changed from "A" to "B"`.
 */
export function describeScheduleChange(c: ScheduleChange): string {
  const what = `${c.kind === "item" ? "Item" : "Alternate"} ${c.position}`;
  if (c.change === "added") return `${what} added: ${c.after ?? ""}`;
  if (c.change === "removed") return `${what} removed: ${c.before ?? ""}`;
  return `${what} changed from "${c.before ?? ""}" to "${c.after ?? ""}"`;
}
