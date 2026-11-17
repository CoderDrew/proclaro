import type { SessionContext } from "@/lib/session";
import { cleanText, isAdminCtx, NOT_ADMIN, type AdminResult } from "../common";

export interface SettingsDeps {
  /** Returns false when no settings row exists to update. */
  update(row: { state_name: string; office_name: string; timezone: string; fiscal_year_start_month: number }): Promise<boolean>;
}

export function ianaZones(): string[] {
  return Intl.supportedValuesOf("timeZone");
}

export function isIanaZone(tz: string): boolean {
  return ianaZones().includes(tz);
}

export async function saveSettings(
  ctx: SessionContext,
  input: { stateName: unknown; officeName: unknown; timezone: unknown; fiscalYearStartMonth: unknown },
  d: SettingsDeps,
): Promise<AdminResult> {
  if (!isAdminCtx(ctx)) return NOT_ADMIN;
  const state = cleanText(input.stateName, "State name");
  if ("error" in state) return { ok: false, message: state.error };
  const office = cleanText(input.officeName, "Office name");
  if ("error" in office) return { ok: false, message: office.error };
  if (typeof input.timezone !== "string" || !isIanaZone(input.timezone)) {
    return { ok: false, message: "Choose a time zone from the list." };
  }
  const monthText = typeof input.fiscalYearStartMonth === "string" ? input.fiscalYearStartMonth.trim() : "";
  const month = /^\d{1,2}$/.test(monthText) ? Number(monthText) : NaN;
  if (!(month >= 1 && month <= 12)) return { ok: false, message: "Fiscal year start month must be a whole number from 1 to 12." };

  const found = await d.update({
    state_name: state.value, office_name: office.value, timezone: input.timezone, fiscal_year_start_month: month,
  });
  return found ? { ok: true, message: "Settings saved." } : { ok: false, message: "The settings row was not found or could not be updated." };
}
