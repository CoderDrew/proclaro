// Pure, server-free logic behind the office addendum review screens. Kept out of the "use server" file so it can be
// tested with injected deps and so clients can never pass their own `deps` to a server action.
import { messageFor } from "../../logic";

export type AddendumActionResult = { ok: true; message?: string } | { ok: false; message: string };

export type AddendumOfficeRpc =
  | "start_addendum_review" | "reassign_addendum_review" | "return_addendum" | "send_addendum_to_check"
  | "approve_addendum_check" | "disagree_addendum" | "approve_addendum_alone" | "reopen_addendum_review"
  | "withdraw_addendum" | "close_question";

export interface AddendumOfficeDeps {
  /** Calls a database function as the signed-in user; throws Error(<database error code>) on failure. */
  call(fn: AddendumOfficeRpc, args: Record<string, unknown>): Promise<void>;
}

export const CLOSE_REASONS = ["duplicate", "out_of_scope"] as const;
export type CloseReason = (typeof CLOSE_REASONS)[number];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Codes whose shared office copy names "this solicitation"; everything else uses messageFor. */
const ADDENDUM_MESSAGES: Record<string, string> = {
  invalid_state: "This addendum is no longer in the right state for that action. Reload the page.",
  not_found: "That addendum was not found. Reload the page.",
  same_person: "You reviewed this addendum in this round; a different person must check it.",
  reason_required: "Enter a reason.",
  not_open: "Bidding is not open on this solicitation yet.",
};

export function addendumMessageFor(e: unknown): string {
  const code = e instanceof Error ? e.message : "";
  return Object.hasOwn(ADDENDUM_MESSAGES, code) ? ADDENDUM_MESSAGES[code] : messageFor(e);
}

/**
 * The server action wrapper: office-only (the guard throws for anyone else), id-checked, and never throwing for
 * expected errors.
 */
export async function withOffice<R extends { ok: boolean }>(
  guard: () => Promise<unknown>, id: unknown, fn: (id: string) => Promise<R | AddendumActionResult>,
): Promise<R | AddendumActionResult> {
  try {
    await guard();
  } catch (e) {
    return { ok: false, message: addendumMessageFor(e) };
  }
  if (typeof id !== "string" || !UUID.test(id)) return { ok: false, message: addendumMessageFor(new Error("not_found")) };
  try {
    return await fn(id);
  } catch (e) {
    console.error("office addendum action failed", e);
    return { ok: false, message: addendumMessageFor(e) };
  }
}

async function guarded(fn: () => Promise<AddendumActionResult>): Promise<AddendumActionResult> {
  try {
    return await fn();
  } catch (e) {
    return { ok: false, message: addendumMessageFor(e) };
  }
}

const text = (v: unknown) => (typeof v === "string" ? v.trim() : "");

function simple(rpc: AddendumOfficeRpc, done: string) {
  return (id: string, d: AddendumOfficeDeps) =>
    guarded(async () => { await d.call(rpc, { p_addendum_id: id }); return { ok: true, message: done }; });
}

export const startReview = simple("start_addendum_review", "Review started.");
export const sendToCheck = simple("send_addendum_to_check", "Sent to check.");
export const approveCheck = simple("approve_addendum_check", "Approved.");
export const approveAlone = simple("approve_addendum_alone", "Approved alone. Recorded as a single-reviewer approval.");

export const reassign = (id: string, userId: string, d: AddendumOfficeDeps) =>
  guarded(async () => {
    await d.call("reassign_addendum_review", { p_addendum_id: id, p_user: userId });
    return { ok: true, message: "Review reassigned." };
  });

export const returnAddendum = (id: string, comments: { field: string | null; body: string }[], d: AddendumOfficeDeps) =>
  guarded(async () => {
    const clean = (Array.isArray(comments) ? comments : []).map((c) => ({
      field: text(c?.field) === "" ? null : text(c.field),
      body: text(c?.body),
    }));
    if (clean.length === 0 || clean.some((c) => c.body === "")) {
      return { ok: false, message: messageFor(new Error("invalid_comments")) };
    }
    await d.call("return_addendum", { p_addendum_id: id, p_comments: clean });
    return { ok: true, message: "Returned to the agency." };
  });

export const disagree = (id: string, comment: string, d: AddendumOfficeDeps) =>
  guarded(async () => {
    const body = text(comment);
    if (body === "") return { ok: false, message: messageFor(new Error("comment_required")) };
    await d.call("disagree_addendum", { p_addendum_id: id, p_comment: body });
    return { ok: true, message: "Sent back to the reviewer." };
  });

export const reopen = (id: string, reason: string, d: AddendumOfficeDeps) =>
  guarded(async () => {
    const why = text(reason);
    if (why === "") return { ok: false, message: ADDENDUM_MESSAGES.reason_required };
    await d.call("reopen_addendum_review", { p_addendum_id: id, p_reason: why });
    return { ok: true, message: "Reopened for review." };
  });

export const withdraw = (id: string, reason: string, d: AddendumOfficeDeps) =>
  guarded(async () => {
    const why = text(reason);
    if (why === "") return { ok: false, message: ADDENDUM_MESSAGES.reason_required };
    await d.call("withdraw_addendum", { p_addendum_id: id, p_reason: why });
    return { ok: true, message: "Addendum withdrawn." };
  });

export const QUESTION_NOT_FOUND = "That question was not found. Reload the page.";

/** close_question's not_found (and a malformed id) name the question, not an addendum. */
export const closeQuestion = async (questionId: string, reason: CloseReason, d: AddendumOfficeDeps):
  Promise<AddendumActionResult> => {
  if (typeof questionId !== "string" || !UUID.test(questionId)) return { ok: false, message: QUESTION_NOT_FOUND };
  if (!(CLOSE_REASONS as readonly string[]).includes(reason)) {
    return { ok: false, message: "Choose why the question is closed." };
  }
  try {
    await d.call("close_question", { p_question_id: questionId, p_reason: reason });
    return { ok: true, message: "Question closed." };
  } catch (e) {
    const code = e instanceof Error ? e.message : "";
    return { ok: false, message: code === "not_found" ? QUESTION_NOT_FOUND : addendumMessageFor(e) };
  }
};

// ---------------------------------------------------------------------------
// View helpers
// ---------------------------------------------------------------------------

export const ANSWERS_DUE_PASSED = "The answers-due date has passed. Publish anyway?";

/** The publish confirmation body; adds the answers-due sentence when publish_addendum will record after_answers_due. */
export function publishWarning(number: number, afterAnswersDue: boolean): string {
  const base = `Publishing Addendum ${number} renders its documents and makes it public to every bidder. It cannot be undone.`;
  return afterAnswersDue ? `${base} ${ANSWERS_DUE_PASSED}` : base;
}

const CLOSE_LABELS: Record<string, string> = { duplicate: "duplicate", out_of_scope: "out of scope" };

export function officeQuestionStatus(q: { status: string; answeredInNumber: number | null; closeReason: string | null }): string {
  if (q.status === "answered") return q.answeredInNumber ? `Answered in Addendum ${q.answeredInNumber}` : "Answered";
  if (q.status === "closed") return q.closeReason ? `Closed: ${CLOSE_LABELS[q.closeReason] ?? q.closeReason}` : "Closed";
  return "Open";
}

export interface AddendumAuditRow { id: number; actor: string; action: string; when: string; reason: string | null }

const ACTION_LABELS: Record<string, string> = {
  start_addendum: "Started by the agency", submit_addendum: "Submitted", start_addendum_review: "Review started",
  reassign_addendum_review: "Review reassigned", return_addendum: "Returned to agency",
  send_addendum_to_check: "Sent to check", approve_addendum_check: "Approved by checker",
  disagree_addendum: "Checker disagreed", approve_addendum_alone: "Approved alone (fallback)",
  reopen_addendum_review: "Reopened for review", publish_addendum: "Published", withdraw_addendum: "Withdrawn",
  save_addendum_answer: "Answer saved", remove_addendum_answer: "Answer removed",
};

type Detail = Record<string, unknown>;

function noteFor(action: string, d: Detail, names: Map<string, string>): string | null {
  if (typeof d.reason === "string" && d.reason !== "") return `Reason: ${d.reason}`;
  if (action === "disagree_addendum" && typeof d.comment === "string") return `Comment: ${d.comment}`;
  if (action === "approve_addendum_alone") {
    return "Fallback: no second reviewer available. Recorded as a single-reviewer approval.";
  }
  if (action === "return_addendum" && Array.isArray(d.comments)) {
    return (d.comments as { field?: string | null; body?: string }[])
      .map((c) => (c.field ? `${c.field}: ${c.body ?? ""}` : c.body ?? "")).join(" | ");
  }
  if (action === "reassign_addendum_review") {
    const to = typeof d.new_reviewer_id === "string" ? names.get(d.new_reviewer_id) : null;
    return to ? `New reviewer: ${to}` : null;
  }
  if (action === "publish_addendum" && typeof d.version === "number") {
    return `Published as version ${d.version}${d.after_answers_due === true ? ", after the answers-due date" : ""}.`;
  }
  return null;
}

/** The audit rows for one addendum (newest first, as given), with readable labels and notes. */
export function addendumHistory(
  rows: { id: number; actor_id: string | null; action: string; detail: unknown; created_at: string }[],
  names: Map<string, string>,
  format: (iso: string) => string,
): AddendumAuditRow[] {
  return rows.map((a) => ({
    id: a.id,
    actor: (a.actor_id && names.get(a.actor_id)) || "Agency author",
    action: ACTION_LABELS[a.action] ?? a.action,
    when: format(a.created_at),
    reason: noteFor(a.action, (a.detail ?? {}) as Detail, names),
  }));
}
