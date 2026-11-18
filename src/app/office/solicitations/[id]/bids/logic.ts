// Pure, server-free logic behind the office originals log. Kept out of the "use server" file so it can be tested
// with injected deps and so clients can never pass their own `deps` to a server action.
import { TZDate } from "@date-fns/tz";
import { todayIn, toUtc } from "@/domain/time";
import type { ActionResult } from "../logic";

export type OriginalItem = "signed_form" | "bid_bond";
export const ORIGINAL_ITEMS: readonly OriginalItem[] = ["signed_form", "bid_bond"];
export const ITEM_LABELS: Record<OriginalItem, string> = {
  signed_form: "Signed bid form",
  bid_bond: "Paper bid bond",
};

export interface OriginalsDeps {
  /** The current instant (the database still judges "future" by its own clock). */
  now(): Date;
  /** The configured time zone. */
  tz(): Promise<string>;
  /** Calls a database function as the signed-in user; throws Error(<database error code>) on failure. */
  call(fn: "log_bid_original" | "void_bid_original", args: Record<string, unknown>): Promise<void>;
}

const MSG = {
  future: "The received time can't be in the future.",
  badTime: "Enter the received date and time.",
  reference: "Enter the bid reference.",
  version: "Enter the version number (1 or higher).",
  item: "Choose what was received.",
  reason: "Enter a reason for the void.",
  notFound: "That log entry was not found.",
  alreadyVoided: "That entry has already been voided.",
  voidOfVoid: "A void can't be voided. Log the item again instead.",
  notAuthorized: "You are not allowed to do that.",
  generic: "Something went wrong. Reload the page and try again.",
} as const;

/** A `datetime-local` value (YYYY-MM-DDTHH:mm, optional :ss) in the configured zone. Blank means "now" (null). */
export function parseReceivedAt(
  local: string, tz: string, now: Date,
): { ok: true; at: Date | null } | { ok: false; message: string } {
  const s = typeof local === "string" ? local.trim() : "";
  if (s === "") return { ok: true, at: null };
  const m = /^(\d{4}-\d{2}-\d{2})T(\d{2}:\d{2})(?::\d{2}(?:\.\d+)?)?$/.exec(s);
  if (!m) return { ok: false, message: MSG.badTime };
  let at: Date;
  try {
    at = toUtc(m[1], m[2], tz);
  } catch {
    return { ok: false, message: MSG.badTime };
  }
  if (Number.isNaN(at.getTime())) return { ok: false, message: MSG.badTime };
  if (at.getTime() > now.getTime()) return { ok: false, message: MSG.future };
  return { ok: true, at };
}

/** The current minute in the configured zone as a `datetime-local` value. (The form defaults to blank = database now().) */
export function localInputValue(now: Date, tz: string): string {
  const z = new TZDate(now.getTime(), tz);
  const p = (n: number) => String(n).padStart(2, "0");
  return `${todayIn(tz, now)}T${p(z.getHours())}:${p(z.getMinutes())}`;
}

/** A positive whole version number that fits a Postgres int, or null. */
export function parseVersion(s: string): number | null {
  const t = typeof s === "string" ? s.trim() : "";
  if (!/^[1-9]\d{0,9}$/.test(t)) return null;
  const n = Number(t);
  return n <= 2_147_483_647 ? n : null;
}

/** The reference as the database will read it (app.normalize_bid_reference), for messages; else trimmed input. */
export function displayReference(ref: string): string {
  const s = ref.replace(/[\s-]/g, "").toUpperCase().replace(/O/g, "0").replace(/[IL]/g, "1");
  return /^[0-9A-HJKMNP-TV-Z]{8}$/.test(s) ? `${s.slice(0, 4)}-${s.slice(4)}` : ref.trim();
}

function codeOf(e: unknown): string {
  return e instanceof Error ? e.message : "";
}

export interface LogOriginalInput {
  reference: string;
  version: string;
  item: string;
  /** `datetime-local` in the configured zone; blank means now. */
  receivedAt: string;
}

export async function runLogOriginal(
  solicitationId: string, input: LogOriginalInput, d: OriginalsDeps,
): Promise<ActionResult> {
  const reference = typeof input?.reference === "string" ? input.reference.trim() : "";
  if (reference === "") return { ok: false, message: MSG.reference };
  const version = parseVersion(input.version);
  if (version === null) return { ok: false, message: MSG.version };
  if (!ORIGINAL_ITEMS.includes(input.item as OriginalItem)) return { ok: false, message: MSG.item };
  const received = parseReceivedAt(input.receivedAt, await d.tz(), d.now());
  if (!received.ok) return received;

  try {
    await d.call("log_bid_original", {
      p_solicitation_id: solicitationId, p_reference: reference, p_version: version, p_item: input.item,
      ...(received.at ? { p_received_at: received.at.toISOString() } : {}),
    });
    return { ok: true };
  } catch (e) {
    switch (codeOf(e)) {
      case "unknown_bid":
        return { ok: false, message: `No submitted bid ${displayReference(reference)} version ${version} on this solicitation.` };
      case "received_in_future": return { ok: false, message: MSG.future };
      case "invalid_data": return { ok: false, message: MSG.item };
      case "not_authorized": return { ok: false, message: MSG.notAuthorized };
      default: return { ok: false, message: MSG.generic };
    }
  }
}

export async function runVoidOriginal(entryId: string, reason: string, d: OriginalsDeps): Promise<ActionResult> {
  const why = typeof reason === "string" ? reason.trim() : "";
  if (why === "") return { ok: false, message: MSG.reason };
  try {
    await d.call("void_bid_original", { p_entry_id: entryId, p_reason: why });
    return { ok: true };
  } catch (e) {
    switch (codeOf(e)) {
      case "reason_required": return { ok: false, message: MSG.reason };
      case "not_found": return { ok: false, message: MSG.notFound };
      case "already_voided": return { ok: false, message: MSG.alreadyVoided };
      case "invalid_state": return { ok: false, message: MSG.voidOfVoid };
      case "not_authorized": return { ok: false, message: MSG.notAuthorized };
      default: return { ok: false, message: MSG.generic };
    }
  }
}
