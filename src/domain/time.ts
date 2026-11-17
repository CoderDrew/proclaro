import { TZDate } from "@date-fns/tz";

export type LocalDate = string; // YYYY-MM-DD
export type LocalTime = string; // HH:mm

const DAY_MS = 86_400_000;

function parseDate(d: LocalDate): [number, number, number] {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(d);
  if (!m) throw new Error(`Invalid LocalDate: ${d}`);
  return [Number(m[1]), Number(m[2]), Number(m[3])];
}

function toEpochDay(d: LocalDate): number {
  const [y, mo, da] = parseDate(d);
  return Date.UTC(y, mo - 1, da) / DAY_MS;
}

function fromEpochDay(n: number): LocalDate {
  return new Date(n * DAY_MS).toISOString().slice(0, 10);
}

export function toUtc(date: LocalDate, time: LocalTime, tz: string): Date {
  const [y, mo, da] = parseDate(date);
  const t = /^(\d{2}):(\d{2})$/.exec(time);
  if (!t) throw new Error(`Invalid LocalTime: ${time}`);
  return new Date(new TZDate(y, mo - 1, da, Number(t[1]), Number(t[2]), 0, tz).getTime());
}

export function todayIn(tz: string, now: Date): LocalDate {
  const z = new TZDate(now.getTime(), tz);
  const p = (n: number, w = 2) => String(n).padStart(w, "0");
  return `${p(z.getFullYear(), 4)}-${p(z.getMonth() + 1)}-${p(z.getDate())}`;
}

export function addDays(d: LocalDate, n: number): LocalDate {
  return fromEpochDay(toEpochDay(d) + n);
}

/** a - b in calendar days. */
export function diffDays(a: LocalDate, b: LocalDate): number {
  return toEpochDay(a) - toEpochDay(b);
}

export function isWeekend(d: LocalDate): boolean {
  const dow = new Date(toEpochDay(d) * DAY_MS).getUTCDay();
  return dow === 0 || dow === 6;
}

export function isNonWorkingDay(d: LocalDate, holidays: LocalDate[]): boolean {
  return isWeekend(d) || holidays.includes(d);
}

/** The calendar year in which the fiscal year containing `d` ends. */
export function fiscalYearOf(d: LocalDate, startMonth: number): number {
  const [y, mo] = parseDate(d);
  return startMonth === 1 ? y : mo >= startMonth ? y + 1 : y;
}
