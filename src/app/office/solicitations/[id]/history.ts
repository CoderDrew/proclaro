import { formatMoney } from "@/domain/money";

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const dateFmt = new Intl.DateTimeFormat("en-US", { timeZone: "UTC", dateStyle: "medium" });

/** One stored value, readable: cents as money, calendar dates as "Dec 17, 2026", blanks as "(blank)". */
export function formatValue(key: string, v: unknown): string {
  if (v === null || v === undefined || v === "") return "(blank)";
  if (key === "estimateCents" && typeof v === "number") return formatMoney(v);
  if (typeof v === "string") return DATE.test(v) ? dateFmt.format(new Date(`${v}T00:00:00Z`)) : v;
  if (typeof v === "object" && !Array.isArray(v)) {
    const o = v as Record<string, unknown>;
    if (typeof o.date === "string" && typeof o.time === "string" && DATE.test(o.date)) {
      return `${dateFmt.format(new Date(`${o.date}T00:00:00Z`))} ${o.time}`;
    }
  }
  const json = JSON.stringify(v);
  return json.length > 160 ? `${json.slice(0, 157)}...` : json;
}

/** "bidDueDate: Dec 16, 2026 -> Dec 17, 2026" for each change stored by office_update_data. */
export function describeChanges(changes: unknown): string[] {
  if (!Array.isArray(changes)) return [];
  return (changes as { key?: string; old?: unknown; new?: unknown }[])
    .filter((c) => typeof c.key === "string")
    .map((c) => `${c.key}: ${formatValue(c.key!, c.old)} → ${formatValue(c.key!, c.new)}`);
}
