import { toUtc, type LocalDate, type LocalTime } from "../domain/time";

const MONTHS = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

export const TBD = "To be determined";

export function formatDate(d: LocalDate | null): string {
  if (!d) return TBD;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(d);
  if (!m) return d;
  return `${MONTHS[Number(m[2]) - 1]} ${Number(m[3])}, ${m[1]}`;
}

export function formatTime(t: LocalTime): string {
  const m = /^(\d{2}):(\d{2})$/.exec(t);
  if (!m) return t;
  const h = Number(m[1]);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${m[2]} ${h < 12 ? "AM" : "PM"}`;
}

/** Short zone name (MDT, MST...) in effect on that local date and time. */
export function zoneAbbr(date: LocalDate, time: LocalTime, tz: string): string {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: tz, timeZoneName: "short" })
    .formatToParts(toUtc(date, time, tz));
  return parts.find((p) => p.type === "timeZoneName")?.value ?? tz;
}

export function formatTimeWithZone(date: LocalDate | null, time: LocalTime, tz: string): string {
  return date ? `${formatTime(time)} ${zoneAbbr(date, time, tz)}` : formatTime(time);
}

export function formatDateTime(v: { date: LocalDate; time: LocalTime } | null, tz: string): string {
  if (!v) return TBD;
  return `${formatDate(v.date)}, ${formatTimeWithZone(v.date, v.time, tz)}`;
}
