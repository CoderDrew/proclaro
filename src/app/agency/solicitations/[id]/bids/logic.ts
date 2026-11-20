// Pure, server-free logic behind the agency's flagged-bid decisions. Kept out of the "use server" file so it can be
// tested with injected deps and so clients can never pass their own `deps` to a server action.
import type { Database } from "@/lib/supabase/database.types";

export type FlagDecision = Database["public"]["Enums"]["flag_decision"];

export type FlaggedResult = { ok: true; message: string } | { ok: false; message: string };

export const DECISIONS: readonly FlagDecision[] = ["accept", "reject"];
export const DECISION_LABELS: Record<FlagDecision, string> = {
  accept: "Accept the bid",
  reject: "Reject the bid",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const MSG = {
  outcome: "That flagged bid was not found. Reload the page and try again.",
  decision: "Choose accept or reject.",
  reason: "Enter a reason.",
  generic: "Something went wrong. Reload the page and try again.",
} as const;

/** Plain copy for every database error code the flagged-bid functions raise. */
const CODES: Record<string, string> = {
  not_authorized: "You are not allowed to do that.",
  not_found: MSG.outcome,
  sealed: "Bids are still sealed. Flagged bids can be decided only after the bid due time.",
  invalid_state: "This bid can no longer be decided here. The office may have changed its review. Reload the page.",
  reason_required: MSG.reason,
  invalid_data: MSG.decision,
};

function codeOf(e: unknown): string {
  if (e && typeof e === "object" && "message" in e && typeof (e as { message: unknown }).message === "string") {
    return (e as { message: string }).message;
  }
  return "";
}

export function flaggedMessageFor(e: unknown): string {
  const code = codeOf(e);
  return Object.hasOwn(CODES, code) ? CODES[code] : MSG.generic;
}

function text(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

export function parseDecisionForm(form: Record<string, unknown>):
  | { ok: true; value: { outcomeId: string; decision: FlagDecision; reason: string } }
  | { ok: false; message: string } {
  const outcomeId = text(form.outcomeId);
  if (!UUID.test(outcomeId)) return { ok: false, message: MSG.outcome };
  const decision = text(form.decision);
  if (!DECISIONS.includes(decision as FlagDecision)) return { ok: false, message: MSG.decision };
  const reason = text(form.reason);
  if (reason === "") return { ok: false, message: MSG.reason };
  return { ok: true, value: { outcomeId, decision: decision as FlagDecision, reason } };
}

export interface FlaggedDeps {
  /** Calls decide_flagged_bid as the signed-in user; throws an error whose message is the database code. */
  decide(args: { p_outcome_id: string; p_decision: FlagDecision; p_reason: string }): Promise<void>;
}

export async function runDecideFlagged(form: Record<string, unknown>, d: FlaggedDeps): Promise<FlaggedResult> {
  const p = parseDecisionForm(form);
  if (!p.ok) return p;
  try {
    await d.decide({ p_outcome_id: p.value.outcomeId, p_decision: p.value.decision, p_reason: p.value.reason });
    return { ok: true, message: p.value.decision === "accept" ? "Decision saved: accepted." : "Decision saved: rejected." };
  } catch (e) {
    return { ok: false, message: flaggedMessageFor(e) };
  }
}

/** The review status the decision gives the bid, for the shared review badge ("Flagged for agency", ...). */
export function decisionStatus(decision: FlagDecision | null): "flagged" | "flag_accepted" | "flag_rejected" {
  return decision === "accept" ? "flag_accepted" : decision === "reject" ? "flag_rejected" : "flagged";
}

/** Decisions are possible only while the office is still reviewing (stage bid_review) and after it sent the flags. */
export function canDecide(stage: string | null, flagsReleasedAt: string | null): boolean {
  return stage === "bid_review" && flagsReleasedAt !== null;
}

/** Accessible names for controls that repeat once per bid, so each one says which bid it acts on. */
export function rowLabel(reference: string): string {
  return `Save decision for bid ${reference}`;
}

// ---------------------------------------------------------------------------
// Award pick: the agency chooses a bid from the posted recap. public.pick_award enforces every rule; parsePick only
// checks the form against the posted recap so the agency gets the reason message before a round trip.
// ---------------------------------------------------------------------------

export type PickResult = FlaggedResult;

const PICK_MSG = {
  bid: "Choose a bidder from the recap.",
  differs: "Explain why this bid differs from the expected award.",
  tied: "Explain the choice between tied bids.",
  solicitation: "That solicitation was not found. Reload the page and try again.",
  noRecap: "The recap is not posted, so no award can be chosen yet. Reload the page.",
} as const;

/** Plain copy for every database error code public.pick_award raises. */
const PICK_CODES: Record<string, string> = {
  not_authorized: "You are not allowed to do that.",
  sealed: "Bids are still sealed.",
  invalid_state: "The award can no longer be chosen here. The office may be checking it. Reload the page.",
  not_in_recap: PICK_MSG.bid,
  reason_required: "Enter a reason for this choice.",
};

export function pickMessageFor(e: unknown): string {
  const code = codeOf(e);
  return Object.hasOwn(PICK_CODES, code) ? PICK_CODES[code] : MSG.generic;
}

/** The minimum of the posted recap the pick rules need. */
export interface PickRecap {
  rows: readonly { bidId: string }[];
  expectedWinnerBidId: string | null;
}

/**
 * Why a reason is required for choosing bidId, or null when it is not: any pick when rank 1 is tied (no expected
 * winner), or a pick other than the expected winner.
 */
export function pickReasonRule(recap: PickRecap, bidId: string): "tied" | "differs" | null {
  if (recap.expectedWinnerBidId === null) return "tied";
  return bidId === recap.expectedWinnerBidId ? null : "differs";
}

export function parsePick(form: Record<string, unknown>, recap: PickRecap):
  | { ok: true; value: { bidId: string; reason: string | null } }
  | { ok: false; message: string } {
  const bidId = text(form.bidId);
  if (!recap.rows.some((r) => r.bidId === bidId)) return { ok: false, message: PICK_MSG.bid };
  const reason = text(form.reason);
  const rule = pickReasonRule(recap, bidId);
  if (reason === "" && rule === "tied") return { ok: false, message: PICK_MSG.tied };
  if (reason === "" && rule === "differs") return { ok: false, message: PICK_MSG.differs };
  return { ok: true, value: { bidId, reason: reason === "" ? null : reason } };
}

export interface PickDeps {
  /** The posted recap of kind "recap" for the solicitation (public.recaps), or null. */
  postedRecap(solicitationId: string): Promise<PickRecap | null>;
  /** Calls pick_award as the signed-in user; throws an error whose message is the database code. */
  pick(args: { p_solicitation_id: string; p_bid_id: string; p_reason: string | null }): Promise<void>;
}

export async function runPickAward(form: Record<string, unknown>, d: PickDeps): Promise<PickResult> {
  const solicitationId = text(form.solicitationId);
  if (!UUID.test(solicitationId)) return { ok: false, message: PICK_MSG.solicitation };
  const recap = await d.postedRecap(solicitationId);
  if (!recap) return { ok: false, message: PICK_MSG.noRecap };
  const p = parsePick(form, recap);
  if (!p.ok) return p;
  try {
    await d.pick({ p_solicitation_id: solicitationId, p_bid_id: p.value.bidId, p_reason: p.value.reason });
    return { ok: true, message: "Award choice recorded. The procurement office will post the award." };
  } catch (e) {
    return { ok: false, message: pickMessageFor(e) };
  }
}

/** The agency may record a choice only while the recap is posted and the office has not sent the award to check. */
export function canPick(stage: string | null): boolean {
  return stage === "recap_posted";
}
