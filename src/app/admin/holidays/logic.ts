import type { SessionContext } from "@/lib/session";
import { cleanText, isAdminCtx, NOT_ADMIN, type AdminResult } from "../common";

export interface HolidayDeps {
  insert(row: { day: string; name: string }): Promise<"ok" | "duplicate">;
  /** Returns false when nothing matched. */
  remove(day: string): Promise<boolean>;
}

/** A real calendar date written YYYY-MM-DD (rejects 2027-02-30 and similar). */
export function isValidLocalDate(s: unknown): s is string {
  if (typeof s !== "string") return false;
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (!m) return false;
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  const dt = new Date(Date.UTC(y, mo - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === mo - 1 && dt.getUTCDate() === d;
}

export async function addHoliday(ctx: SessionContext, input: { day: unknown; name: unknown }, d: HolidayDeps): Promise<AdminResult> {
  if (!isAdminCtx(ctx)) return NOT_ADMIN;
  if (!isValidLocalDate(input.day)) return { ok: false, message: "Enter a real date as YYYY-MM-DD." };
  const name = cleanText(input.name, "Holiday name");
  if ("error" in name) return { ok: false, message: name.error };
  const res = await d.insert({ day: input.day, name: name.value });
  return res === "ok" ? { ok: true, message: "Holiday added." } : { ok: false, message: "That date is already a holiday." };
}

export async function removeHoliday(ctx: SessionContext, day: unknown, d: HolidayDeps): Promise<AdminResult> {
  if (!isAdminCtx(ctx)) return NOT_ADMIN;
  if (!isValidLocalDate(day)) return { ok: false, message: "Enter a real date as YYYY-MM-DD." };
  return (await d.remove(day)) ? { ok: true, message: "Holiday removed." } : { ok: false, message: "That holiday was not found." };
}
