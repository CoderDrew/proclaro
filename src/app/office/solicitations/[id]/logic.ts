// Pure, server-free logic behind the office actions. Kept out of the "use server" file so it can be
// tested with injected deps and so clients can never pass their own `deps` to a server action.
import { ZodError } from "zod";
import { prepareDraftData, unacknowledgedWarnings } from "@/app/agency/solicitations/[id]/logic";
import { todayIn } from "@/domain/time";
import type { SolicitationData } from "@/domain/solicitation/types";
import { validate, type Issue } from "@/domain/solicitation/validate";

export type ActionResult =
  | { ok: true }
  | { ok: false; message: string; errors?: Issue[]; unacknowledged?: Issue[] };

export type OfficeRpc =
  | "start_review" | "reassign_review" | "office_update_data" | "return_to_agency"
  | "send_to_check" | "approve_check" | "disagree" | "approve_alone" | "acknowledge_warning" | "reopen_review";

export interface OfficeDeps {
  /** The current instant; "today" is always computed from it in the configured zone. */
  now(): Date;
  /** Calls a database function as the signed-in user; throws Error(<database error code>) on failure. */
  call(fn: OfficeRpc, args: Record<string, unknown>): Promise<void>;
  /** The stored row as the caller sees it (RLS), or null when invisible. */
  loadRow(id: string): Promise<{ data: SolicitationData; state: string; latestSubmittedAt: string | null } | null>;
  settings(): Promise<{ tz: string; holidays: string[] }>;
  loadAcks(id: string): Promise<{ code: string; field: string | null }[]>;
}

/** Shared with publish: the same code and message whether the gate or publish finds the passed date. */
export const RELEASE_PASSED = "Release date has passed; correct the dates before publishing";
export const INVALID_STORED_DATA = "This solicitation's data is invalid; return it to the agency.";

const MESSAGES: Record<string, string> = {
  invalid_state: "This solicitation is no longer in the right state for that action. Reload the page.",
  same_person: "You reviewed this solicitation; a different person must check it.",
  reason_required: "Enter a reason for the change.",
  comment_required: "Enter a comment.",
  invalid_comments: "Add at least one comment, and give every comment some text.",
  not_authorized: "You are not allowed to do that.",
  not_found: "That solicitation was not found.",
  invalid_data: "The solicitation data is not valid.",
  invalid_release_date: RELEASE_PASSED,
  invalid_stored_data: INVALID_STORED_DATA,
  invalid_paths: "The published files are not where this solicitation expects them. Try publishing again.",
  bid_due_mismatch: "The bid due time could not be confirmed. Reload the page and try again.",
  snapshot_mismatch: "The funding amount changed while publishing. Reload the page and try again.",
};

/** Maps a thrown database/guard error to a user message. Unknown errors get a generic message. */
export function messageFor(e: unknown): string {
  if (e instanceof ZodError) {
    const first = e.issues[0];
    return `The data is not valid${first ? ` (${first.path.join(".") || "root"}: ${first.message})` : ""}.`;
  }
  const code = e instanceof Error ? e.message : "";
  if (code === "invalid_attachment_path") return "An attachment does not belong to this solicitation.";
  return MESSAGES[code] ?? "Something went wrong. Reload the page and try again.";
}

async function guarded(fn: () => Promise<ActionResult>): Promise<ActionResult> {
  try {
    return await fn();
  } catch (e) {
    return { ok: false, message: messageFor(e) };
  }
}

const idArg = (id: string) => ({ p_id: id });

export const startReview = (id: string, d: OfficeDeps) =>
  guarded(async () => { await d.call("start_review", idArg(id)); return { ok: true }; });

export const reassign = (id: string, userId: string, d: OfficeDeps) =>
  guarded(async () => { await d.call("reassign_review", { p_id: id, p_user: userId }); return { ok: true }; });

export const approveCheck = (id: string, d: OfficeDeps) =>
  guarded(async () => { await d.call("approve_check", idArg(id)); return { ok: true }; });

export const acknowledge = (id: string, code: string, field: string | null, d: OfficeDeps) =>
  guarded(async () => {
    // The database function does not normalize '' to null, so do it here.
    await d.call("acknowledge_warning", { p_id: id, p_code: code, p_field: field === "" ? null : field });
    return { ok: true };
  });

/** Replaces the whole data object: the caller must send complete data, which is Zod-parsed here. */
export const editAsReviewer = (id: string, input: unknown, reason: string, d: OfficeDeps) =>
  guarded(async () => {
    const why = typeof reason === "string" ? reason.trim() : "";
    if (why === "") return { ok: false, message: MESSAGES.reason_required };
    const data = prepareDraftData(id, input);
    await d.call("office_update_data", { p_id: id, p_data: JSON.parse(JSON.stringify(data)), p_reason: why });
    return { ok: true };
  });

export const returnToAgency = (id: string, comments: { field: string | null; body: string }[], d: OfficeDeps) =>
  guarded(async () => {
    const clean = (Array.isArray(comments) ? comments : []).map((c) => ({
      field: c.field && c.field.trim() !== "" ? c.field.trim() : null,
      body: typeof c.body === "string" ? c.body.trim() : "",
    }));
    if (clean.length === 0 || clean.some((c) => c.body === "")) return { ok: false, message: MESSAGES.invalid_comments };
    await d.call("return_to_agency", { p_id: id, p_comments: clean });
    return { ok: true };
  });

export const disagree = (id: string, comment: string, field: string | null, d: OfficeDeps) =>
  guarded(async () => {
    const body = typeof comment === "string" ? comment.trim() : "";
    if (body === "") return { ok: false, message: MESSAGES.comment_required };
    const f = field && field.trim() !== "" ? field.trim() : null;
    await d.call("disagree", { p_id: id, p_comment: body, p_field: f });
    return { ok: true };
  });

/** The date (in the configured zone) of the latest submission, which anchors the release-date rule. */
export function submissionDateOf(latestSubmittedAt: string | null, tz: string): string {
  return todayIn(tz, latestSubmittedAt ? new Date(latestSubmittedAt) : new Date());
}

/** The release_too_soon issue when the release date is before today in the configured zone, else null. */
export function releasePassed(data: SolicitationData, tz: string, now: Date): Issue | null {
  return data.releaseDate !== null && data.releaseDate < todayIn(tz, now)
    ? { code: "release_too_soon", field: "releaseDate", message: RELEASE_PASSED }
    : null;
}

/**
 * Re-validates the stored row (never client data) with the latest submission date; refuses with the
 * errors and unacknowledged warnings, otherwise calls the database function.
 */
function gated(rpc: "send_to_check" | "approve_alone") {
  return (id: string, d: OfficeDeps): Promise<ActionResult> =>
    guarded(async () => {
      const row = await d.loadRow(id);
      if (!row) return { ok: false, message: MESSAGES.not_found };
      if (row.state !== "in_review") return { ok: false, message: MESSAGES.invalid_state };

      const { tz, holidays } = await d.settings();
      const { errors, warnings } = validate(row.data, {
        tz, holidays, submissionDate: submissionDateOf(row.latestSubmittedAt, tz),
      });
      // The 3-day rule is anchored on the latest submission, so a release date that has since passed is
      // checked against today separately: an approval with a stale date could never be published.
      const passed = releasePassed(row.data, tz, d.now());
      if (passed) errors.unshift(passed);
      const acks = warnings.length > 0 ? await d.loadAcks(id) : [];
      const unacknowledged = unacknowledgedWarnings(warnings, acks);
      if (errors.length > 0 || unacknowledged.length > 0) {
        return {
          ok: false,
          message: "Fix every problem and acknowledge every warning first.",
          errors,
          unacknowledged,
        };
      }
      await d.call(rpc, idArg(id));
      return { ok: true };
    });
}

/**
 * Approved -> in review, so the reviewer can correct the dates (spec 7.1). The reviewer or checker may reopen; a
 * reason is required and recorded. The database clears the checker and fallback flag and drops the clause locks.
 */
export const reopenReview = (id: string, reason: string, d: OfficeDeps) =>
  guarded(async () => {
    const why = typeof reason === "string" ? reason.trim() : "";
    if (why === "") return { ok: false, message: MESSAGES.reason_required };
    await d.call("reopen_review", { p_id: id, p_reason: why });
    return { ok: true };
  });

export const sendToCheck = gated("send_to_check");
export const approveAlone = gated("approve_alone");
