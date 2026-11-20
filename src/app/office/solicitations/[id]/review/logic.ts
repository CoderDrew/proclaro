// Pure, server-free logic behind the office bid review screen. Kept out of the "use server" file so it can be tested
// with injected deps and so clients can never pass their own `deps` to a server action.
import type { Database } from "@/lib/supabase/database.types";

export type BidOutcome = Database["public"]["Enums"]["bid_outcome"];
export type NonResponsiveGround = Database["public"]["Enums"]["non_responsive_ground"];

export type ReviewResult = { ok: true; message: string } | { ok: false; message: string };

export const OUTCOMES: readonly BidOutcome[] = ["accepted", "accepted_flagged", "non_responsive"];
export const OUTCOME_LABELS: Record<BidOutcome, string> = {
  accepted: "Accept",
  accepted_flagged: "Accept and flag for the agency",
  non_responsive: "Non-responsive",
};

export const GROUNDS: readonly NonResponsiveGround[] = ["late_upload", "wrong_form", "missing_signature"];
export const GROUND_LABELS: Record<NonResponsiveGround, string> = {
  late_upload: "Late upload",
  wrong_form: "Wrong form",
  missing_signature: "Missing signature",
};

/** The two reasons the database sets on its own; no function lets anyone change them. */
export const AUTOMATIC_REASONS: readonly string[] = [
  "signed original not received by the bid due time",
  "bid bond not received by the cure deadline",
];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const MSG = {
  bid: "That bid was not found.",
  outcome: "Choose an outcome.",
  ground: "Choose the non-responsive reason.",
  note: "Enter a reason or note.",
  verdict: "Choose verified or not verified.",
  residentStage: "Resident findings can no longer be changed at this stage.",
  solicitation: "That solicitation was not found.",
  sendState: "No bid is flagged for the agency, or the review has moved on. Reload the page.",
  recapState: "The recap has moved on since this page loaded. Reload the page.",
  awardState: "The award has moved on since this page loaded. Reload the page.",
  comment: "Enter a comment.",
  generic: "Something went wrong. Reload the page and try again.",
} as const;

/** Plain copy for every database error code the review, recap and award functions raise. */
const CODES: Record<string, string> = {
  sealed: "Bids are still sealed. Review opens after the bid due time.",
  not_found: MSG.bid,
  not_authorized: "You are not allowed to do that.",
  outcome_locked: "This outcome is set automatically and cannot be changed.",
  reason_required: MSG.note,
  comment_required: "Enter a comment.",
  invalid_data: "Check the outcome and reason, then try again.",
  invalid_state: "Outcomes can no longer be changed at this stage.",
  invalid_bid: "That bid can't be used here.",
  same_person: "You prepared or reviewed these bids, so a different person must check.",
  snapshot_mismatch: "The bids changed after this page loaded. Reload and try again.",
  cure_closed: "The bid bond cure deadline has passed.",
  cure_pending: "A bid bond cure is still pending. Wait until the cure deadline.",
  undecided_bids: "Set an outcome for every bid first.",
  flags_pending: "The agency has not decided every flagged bid yet.",
  resident_unverified: "Check every resident claim first.",
  recap_stale: "The bids changed after this recap was prepared. Send it back and prepare it again.",
  pick_required: "Choose the bid to award.",
  not_in_recap: "That bid is not in the posted recap.",
};

function codeOf(e: unknown): string {
  if (e && typeof e === "object" && "message" in e && typeof (e as { message: unknown }).message === "string") {
    return (e as { message: string }).message;
  }
  return "";
}

export function reviewMessageFor(e: unknown): string {
  const code = codeOf(e);
  return Object.hasOwn(CODES, code) ? CODES[code] : MSG.generic;
}

function text(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function parseOutcomeForm(form: Record<string, unknown>):
  | { ok: true; value: { bidId: string; outcome: BidOutcome; ground: NonResponsiveGround | null; note: string } }
  | { ok: false; message: string } {
  const bidId = text(form.bidId);
  if (!UUID.test(bidId)) return { ok: false, message: MSG.bid };
  const outcome = text(form.outcome);
  if (!OUTCOMES.includes(outcome as BidOutcome)) return { ok: false, message: MSG.outcome };
  let ground: NonResponsiveGround | null = null;
  if (outcome === "non_responsive") {
    const g = text(form.ground);
    if (!GROUNDS.includes(g as NonResponsiveGround)) return { ok: false, message: MSG.ground };
    ground = g as NonResponsiveGround;
  }
  const note = text(form.note);
  if (note === "") return { ok: false, message: MSG.note };
  return { ok: true, value: { bidId, outcome: outcome as BidOutcome, ground, note } };
}

export function parseVerifyForm(form: Record<string, unknown>):
  | { ok: true; value: { bidId: string; verified: boolean; note: string } }
  | { ok: false; message: string } {
  const bidId = text(form.bidId);
  if (!UUID.test(bidId)) return { ok: false, message: MSG.bid };
  const v = text(form.verified);
  if (v !== "true" && v !== "false") return { ok: false, message: MSG.verdict };
  const note = text(form.note);
  if (note === "") return { ok: false, message: MSG.note };
  return { ok: true, value: { bidId, verified: v === "true", note } };
}

export type ReviewFunction =
  | "set_bid_outcome" | "verify_resident" | "send_flags_to_agency"
  | "send_recap_to_check" | "disagree_recap" | "post_recap" | "post_recap_alone" | "recall_recap"
  | "send_award_to_check" | "disagree_award" | "post_award" | "post_award_alone" | "recall_award";

export interface ReviewDeps {
  /** Calls a database function as the signed-in user; throws an error whose message is the database code. */
  call(fn: ReviewFunction, args: Record<string, unknown>): Promise<void>;
}

export async function runSetOutcome(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  const p = parseOutcomeForm(form);
  if (!p.ok) return p;
  try {
    await d.call("set_bid_outcome", {
      p_bid_id: p.value.bidId, p_outcome: p.value.outcome, p_ground: p.value.ground, p_note: p.value.note,
    });
    return { ok: true, message: "Outcome saved." };
  } catch (e) {
    return { ok: false, message: reviewMessageFor(e) };
  }
}

export async function runVerifyResident(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  const p = parseVerifyForm(form);
  if (!p.ok) return p;
  try {
    await d.call("verify_resident", { p_bid_id: p.value.bidId, p_verified: p.value.verified, p_note: p.value.note });
    return { ok: true, message: "Finding saved." };
  } catch (e) {
    // verify_resident's invalid_state is the stage (or a claim withdrawn since load), not an outcome.
    if (codeOf(e) === "invalid_state") return { ok: false, message: MSG.residentStage };
    return { ok: false, message: reviewMessageFor(e) };
  }
}

/** Sends the flagged bids to the owning agency (public.send_flags_to_agency checks every rule). */
export async function runSendFlags(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  const solicitationId = text(form.solicitationId);
  if (!UUID.test(solicitationId)) return { ok: false, message: MSG.solicitation };
  try {
    await d.call("send_flags_to_agency", { p_solicitation_id: solicitationId });
    return { ok: true, message: "Flagged bids sent to the agency." };
  } catch (e) {
    // send_flags_to_agency's invalid_state is "nothing flagged" or the stage, not an outcome change.
    if (codeOf(e) === "invalid_state") return { ok: false, message: MSG.sendState };
    return { ok: false, message: reviewMessageFor(e) };
  }
}

/**
 * The "Send flagged bids to the agency" button: enabled in bid review, before the first send, when a bid is flagged.
 * After the send, bids flagged later reach the agency at once (agency_flagged_bids reads current outcomes).
 */
export function sendFlagsEnabled(stage: string, flagsReleasedAt: string | null, statuses: readonly string[]): boolean {
  return stage === "bid_review" && flagsReleasedAt === null && statuses.includes("flagged");
}

/** The note above a bid's outcome form: why it is disabled, or what saving means now. */
export function outcomeFormNote(stage: string, status: string, editable: boolean): string | null {
  if (!editable) {
    return stage !== "bid_review"
      ? "Outcomes can no longer be changed at this stage."
      : "This outcome is set automatically and cannot be changed.";
  }
  if (status === "pending_cure") {
    return "The bid bond cure is pending. An outcome saved now takes effect only if the bond is cured in time.";
  }
  if (status === "flag_accepted" || status === "flag_rejected") {
    return "The agency has decided this flagged bid. Saving a new outcome clears the agency's decision.";
  }
  return null;
}

/**
 * The office may set an outcome only in bid review, and never over an automatic non-responsive reason. During a
 * pending cure it may (set_bid_outcome allows it); the status shows the cure until the cure is decided.
 */
export function outcomeEditable(stage: string, status: string, reason: string | null): boolean {
  if (stage !== "bid_review") return false;
  if (status === "non_responsive" && reason !== null && AUTOMATIC_REASONS.includes(reason)) return false;
  return true;
}

export function apprenticeLabel(v: boolean | null): string {
  return v === true ? "Yes" : v === false ? "No" : "—";
}

const CURE_LABELS: Record<string, string> = {
  pending: "Bond cure pending",
  cured: "Bond cured",
  failed: "Bond not received by the cure deadline",
};

/** The bid bond cure, only when one was due (app.bond_cure: pending, cured or failed). */
export function cureView(status: string | null, dueAt: string | null): { label: string; dueAt: string | null } | null {
  if (status === null || !Object.hasOwn(CURE_LABELS, status)) return null;
  return { label: CURE_LABELS[status], dueAt };
}

/** Accessible names for controls that repeat once per bid, so each one says which bid it acts on. */
export function rowLabel(kind: "saveOutcome" | "saveFinding", reference: string): string {
  return kind === "saveOutcome" ? `Save outcome for bid ${reference}` : `Save finding for bid ${reference}`;
}

// ---------------------------------------------------------------------------
// Recap workflow (send to check, disagree, post, post alone). The database enforces every rule; these only check the
// form shape and word the result.
// ---------------------------------------------------------------------------

export type RecapKind = "recap" | "all_rejected";

/** The button and message wording for the recap or the "all bids rejected" memo. */
export function recapWords(kind: RecapKind) {
  const memo = kind === "all_rejected";
  const noun = memo ? "memo" : "recap";
  return {
    noun,
    send: memo ? "Send memo to check" : "Send recap to check",
    post: memo ? "Post memo" : "Post recap",
    postConfirm: memo ? "Confirm: post memo publicly" : "Confirm: post recap publicly",
    alone: "Post alone (no second reviewer available)",
    aloneConfirm: memo
      ? "Confirm: post memo publicly without a second reviewer"
      : "Confirm: post recap publicly without a second reviewer",
    warning: memo
      ? "This makes the memo public, rejects every bid and can't be undone."
      : "This makes the recap public and can't be undone.",
    disagree: "Send back with a comment",
    recall: memo ? "Recall memo to bid review" : "Recall recap to bid review",
    recalled: memo ? "Memo recalled to bid review." : "Recap recalled to bid review.",
    sent: memo ? "Memo sent to check." : "Recap sent to check.",
    posted: memo ? "Memo posted." : "Recap posted.",
    postedAlone: memo ? "Memo posted without a second reviewer." : "Recap posted without a second reviewer.",
    returned: memo ? "Memo sent back to bid review." : "Recap sent back to bid review.",
  };
}

function recapKindOf(v: unknown): RecapKind {
  return text(v) === "all_rejected" ? "all_rejected" : "recap";
}

/** One message per blocker code from preview_recap, in the order the database returned them. */
export function blockerMessages(codes: readonly string[]): string[] {
  return codes.map((c) => reviewMessageFor({ message: c }));
}

/** The recap functions' invalid_state is the stage, and not_found is the solicitation. */
function recapMessageFor(e: unknown): string {
  const code = codeOf(e);
  if (code === "invalid_state") return MSG.recapState;
  if (code === "not_found") return MSG.solicitation;
  return reviewMessageFor(e);
}

async function runRecapCall(
  form: Record<string, unknown>, d: ReviewDeps,
  fn: "send_recap_to_check" | "post_recap" | "post_recap_alone", ok: (w: ReturnType<typeof recapWords>) => string,
): Promise<ReviewResult> {
  const solicitationId = text(form.solicitationId);
  if (!UUID.test(solicitationId)) return { ok: false, message: MSG.solicitation };
  try {
    await d.call(fn, { p_solicitation_id: solicitationId });
    return { ok: true, message: ok(recapWords(recapKindOf(form.kind))) };
  } catch (e) {
    return { ok: false, message: recapMessageFor(e) };
  }
}

export function runSendRecapToCheck(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  return runRecapCall(form, d, "send_recap_to_check", (w) => w.sent);
}

export function runPostRecap(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  return runRecapCall(form, d, "post_recap", (w) => w.posted);
}

export function runPostRecapAlone(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  return runRecapCall(form, d, "post_recap_alone", (w) => w.postedAlone);
}

/** Ruling 13: the sender takes the draft back to bid review (public.recall_recap). */
export async function runRecallRecap(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  const solicitationId = text(form.solicitationId);
  if (!UUID.test(solicitationId)) return { ok: false, message: MSG.solicitation };
  const w = recapWords(recapKindOf(form.kind));
  try {
    await d.call("recall_recap", { p_solicitation_id: solicitationId });
    return { ok: true, message: w.recalled };
  } catch (e) {
    // recall_recap's not_authorized (for an office user) is "you did not send it".
    if (codeOf(e) === "not_authorized") {
      return { ok: false, message: `Only the office user who sent the ${w.noun} to check can recall it.` };
    }
    return { ok: false, message: recapMessageFor(e) };
  }
}

/**
 * Which recap check controls are enabled (from public.recap_draft), with the visible reason. canCheck: a different
 * office user who did not review these bids. canRecall: the sender, who may take it back to bid review.
 */
export function recapCheckControls(canCheck: boolean, canRecall: boolean, kind: RecapKind, preparedBy: string | null): {
  check: boolean; recall: boolean; note: string;
} {
  const noun = recapWords(kind).noun;
  const by = preparedBy ?? "another office user";
  if (canCheck) {
    return { check: true, recall: false,
      note: `Prepared by ${by}. Check it against the bids, then post it or send it back. Posting makes it public.` };
  }
  if (canRecall) {
    return { check: false, recall: true,
      note: `You sent this ${noun} to check, so a different office user who did not review these bids must post it or send it back. If no one else can, recall it to bid review; posting alone is then recorded.` };
  }
  return { check: false, recall: false,
    note: `Prepared by ${by}. You prepared or reviewed these bids, so a different office user must post it or send it back.` };
}

export async function runDisagreeRecap(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  const solicitationId = text(form.solicitationId);
  if (!UUID.test(solicitationId)) return { ok: false, message: MSG.solicitation };
  const comment = text(form.comment);
  if (comment === "") return { ok: false, message: MSG.comment };
  try {
    await d.call("disagree_recap", { p_solicitation_id: solicitationId, p_comment: comment });
    return { ok: true, message: recapWords(recapKindOf(form.kind)).returned };
  } catch (e) {
    return { ok: false, message: recapMessageFor(e) };
  }
}

// ---------------------------------------------------------------------------
// Award workflow (send to check, disagree, post, post alone). The agency's pick is read through
// public.current_award_pick; the database enforces every rule, these only check the form shape and word the result.
// ---------------------------------------------------------------------------

export const AWARD_WORDS = {
  send: "Send award to check",
  post: "Post award",
  postConfirm: "Confirm: post award publicly",
  alone: "Post alone (no second reviewer available)",
  aloneConfirm: "Confirm: post award publicly without a second reviewer",
  warning: "This makes the award public and can't be undone.",
  disagree: "Send back with a comment",
  differs: "Differs from the expected award",
  sent: "Award sent to check.",
  posted: "Award posted.",
  postedAlone: "Award posted without a second reviewer.",
  returned: "Award sent back. The agency can change its choice.",
  newPick: "Ask the agency to record a new award choice first.",
  recall: "Recall award",
  recalled: "Award recalled. You can send it to check again or post it alone.",
} as const;

/** The award functions' invalid_state is the stage, and not_found is the solicitation. */
function awardMessageFor(e: unknown): string {
  const code = codeOf(e);
  if (code === "invalid_state") return MSG.awardState;
  if (code === "not_found") return MSG.solicitation;
  if (code === "same_person") return "You sent this award to check, so a different office user must check it.";
  return reviewMessageFor(e);
}

async function runAwardCall(
  form: Record<string, unknown>, d: ReviewDeps, fn: "send_award_to_check" | "post_award" | "post_award_alone",
  ok: string,
): Promise<ReviewResult> {
  const solicitationId = text(form.solicitationId);
  if (!UUID.test(solicitationId)) return { ok: false, message: MSG.solicitation };
  try {
    await d.call(fn, { p_solicitation_id: solicitationId });
    return { ok: true, message: ok };
  } catch (e) {
    // From recap_posted, send and post alone also raise invalid_state when the pick predates the latest
    // disagreement (Ruling 11); the stage itself is the other cause.
    if (fn !== "post_award" && codeOf(e) === "invalid_state") {
      return { ok: false, message: `${AWARD_WORDS.newPick} If it already has, reload the page.` };
    }
    return { ok: false, message: awardMessageFor(e) };
  }
}

export function runSendAwardToCheck(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  return runAwardCall(form, d, "send_award_to_check", AWARD_WORDS.sent);
}

export function runPostAward(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  return runAwardCall(form, d, "post_award", AWARD_WORDS.posted);
}

export function runPostAwardAlone(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  return runAwardCall(form, d, "post_award_alone", AWARD_WORDS.postedAlone);
}

/** Ruling 13: the sender takes the award back to recap_posted (public.recall_award); the pick stays. */
export async function runRecallAward(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  const solicitationId = text(form.solicitationId);
  if (!UUID.test(solicitationId)) return { ok: false, message: MSG.solicitation };
  try {
    await d.call("recall_award", { p_solicitation_id: solicitationId });
    return { ok: true, message: AWARD_WORDS.recalled };
  } catch (e) {
    if (codeOf(e) === "not_authorized") {
      return { ok: false, message: "Only the office user who sent the award to check can recall it." };
    }
    return { ok: false, message: awardMessageFor(e) };
  }
}

export async function runDisagreeAward(form: Record<string, unknown>, d: ReviewDeps): Promise<ReviewResult> {
  const solicitationId = text(form.solicitationId);
  if (!UUID.test(solicitationId)) return { ok: false, message: MSG.solicitation };
  const comment = text(form.comment);
  if (comment === "") return { ok: false, message: MSG.comment };
  try {
    await d.call("disagree_award", { p_solicitation_id: solicitationId, p_comment: comment });
    return { ok: true, message: AWARD_WORDS.returned };
  } catch (e) {
    return { ok: false, message: awardMessageFor(e) };
  }
}

/**
 * Which award controls are enabled, with the visible reason when they are not. recap_posted: send and post alone
 * need the agency's pick, made after the latest disagreement (needsNewPick from public.award_check_info). award_check:
 * post and disagree need a checker who is not this round's sender (canCheck), so the sender sees them disabled
 * instead of a button that always fails.
 */
export function awardControls(stage: string, hasPick: boolean, canCheck: boolean, needsNewPick = false): {
  send: boolean; alone: boolean; check: boolean; recall: boolean; note: string;
} {
  const none = { send: false, alone: false, check: false, recall: false };
  if (stage === "recap_posted" && hasPick && needsNewPick) {
    return { ...none, note: AWARD_WORDS.newPick };
  }
  if (stage === "recap_posted") {
    return hasPick
      ? { ...none, send: true, alone: true,
          note: "Send the award to a second office user to check. Post alone only when no second reviewer is available; that is recorded." }
      : { ...none, note: "The agency has not chosen a bid from the recap yet." };
  }
  if (stage === "award_check") {
    // award_check_info's can_check is false in award_check only for this round's sender, who may recall it.
    return canCheck
      ? { ...none, check: true, note: "Check the agency's choice against the posted recap, then post it or send it back." }
      : { ...none, recall: true,
          note: "You sent this award to check, so a different office user must post it or send it back. If no one else can, recall it; posting alone is then recorded." };
  }
  return { ...none, note: "The award is not available at this stage." };
}
