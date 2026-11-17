// Shared by the admin logic files (pure: no Next, no Supabase).
import type { SessionContext } from "@/lib/session";

export type AdminResult = { ok: true; message?: string } | { ok: false; message: string };

export const NOT_ADMIN: AdminResult = { ok: false, message: "Only administrators can do that." };

/** True only for a signed-in administrator. Every admin action checks this on the server. */
export function isAdminCtx(ctx: SessionContext): ctx is NonNullable<SessionContext> {
  return !!ctx && ctx.isAdmin === true;
}

/** Postgres unique-violation (23505) as surfaced by supabase-js. */
export function isUniqueViolation(err: { code?: string } | null | undefined): boolean {
  return err?.code === "23505";
}

/** Required-text check shared by the forms: trims and rejects blank or oversize input. */
export function cleanText(v: unknown, label: string, max = 200): { value: string } | { error: string } {
  if (typeof v !== "string" || v.trim() === "") return { error: `${label} is required.` };
  const value = v.trim();
  if (value.length > max) return { error: `${label} must be at most ${max} characters.` };
  return { value };
}
