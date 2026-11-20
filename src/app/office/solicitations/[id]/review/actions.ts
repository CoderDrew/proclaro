"use server";

import { createServerClient } from "@/lib/supabase/server";
import { requireOfficeAction } from "../../../guard";
import {
  runDisagreeAward, runDisagreeRecap, runPostAward, runPostAwardAlone, runPostRecap, runPostRecapAlone,
  runRecallAward, runRecallRecap, runSendAwardToCheck, runSendFlags, runSendRecapToCheck, runSetOutcome,
  runVerifyResident, type ReviewDeps, type ReviewResult,
} from "./logic";

const NOT_AUTHORIZED: ReviewResult = { ok: false, message: "You are not allowed to do that." };
const GENERIC: ReviewResult = { ok: false, message: "Something went wrong. Reload the page and try again." };

/** Dependencies bound to the caller's own client (never the admin client). */
async function reviewDeps(): Promise<ReviewDeps> {
  const supabase = await createServerClient();
  return {
    async call(fn, args) {
      // Argument shapes are fixed by logic.ts; the generated rpc types are per-function unions.
      const { error } = await supabase.rpc(fn, args as never);
      if (error) throw new Error(error.message);
    },
  };
}

function fields(formData: FormData): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of ["bidId", "outcome", "ground", "note", "verified", "solicitationId", "kind", "comment"]) {
    const v = formData.get(k);
    if (typeof v === "string") out[k] = v;
  }
  return out;
}

/** Office only. Records an outcome for one bid (an append-only row; the latest is current). */
export async function setOutcome(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  try {
    await requireOfficeAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  try {
    return await runSetOutcome(fields(formData), await reviewDeps());
  } catch (e) {
    console.error("set outcome failed", e);
    return GENERIC;
  }
}

/** Office only. Records the office's finding on a bid's resident certificate claim. */
export async function verifyResident(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  try {
    await requireOfficeAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  try {
    return await runVerifyResident(fields(formData), await reviewDeps());
  } catch (e) {
    console.error("verify resident failed", e);
    return GENERIC;
  }
}

/** Office only. Sends the flagged bids to the owning agency (sets flags_released_at once; audited). */
export async function sendFlags(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  try {
    await requireOfficeAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  try {
    return await runSendFlags(fields(formData), await reviewDeps());
  } catch (e) {
    console.error("send flags failed", e);
    return GENERIC;
  }
}

/** Runs one office-only review step with the caller's own client; any unexpected failure is a generic message. */
async function officeStep(
  label: string, run: (form: Record<string, unknown>, d: ReviewDeps) => Promise<ReviewResult>, formData: FormData,
): Promise<ReviewResult> {
  try {
    await requireOfficeAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  try {
    return await run(fields(formData), await reviewDeps());
  } catch (e) {
    console.error(`${label} failed`, e);
    return GENERIC;
  }
}

/** Office only. Freezes the recap (or memo) draft and sends it to a second office user to check. */
export async function sendRecapToCheck(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("send recap to check", runSendRecapToCheck, formData);
}

/** Office only. The checker sends the draft back to bid review with a comment. */
export async function disagreeRecap(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("disagree recap", runDisagreeRecap, formData);
}

/** Office only. The checker posts the draft; the posted recap is public and cannot change. */
export async function postRecap(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("post recap", runPostRecap, formData);
}

/** Office only. The single-reviewer fallback: posts straight from bid review, recorded as such. */
export async function postRecapAlone(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("post recap alone", runPostRecapAlone, formData);
}

/** Office only. Sends the agency's current award choice to a second office user to check. */
export async function sendAwardToCheck(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("send award to check", runSendAwardToCheck, formData);
}

/** Office only. The checker sends the award back with a comment; the agency can choose again. */
export async function disagreeAward(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("disagree award", runDisagreeAward, formData);
}

/** Office only. The checker posts the award; the posted award is public and cannot change. */
export async function postAward(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("post award", runPostAward, formData);
}

/** Office only. The single-reviewer fallback: posts the award straight from the posted recap, recorded as such. */
export async function postAwardAlone(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("post award alone", runPostAwardAlone, formData);
}

/** Office only, the sender only (Ruling 13). Takes the recap or memo under check back to bid review. */
export async function recallRecap(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("recall recap", runRecallRecap, formData);
}

/** Office only, the sender only (Ruling 13). Takes the award under check back to the posted recap; the pick stays. */
export async function recallAward(_prev: ReviewResult | null, formData: FormData): Promise<ReviewResult> {
  return officeStep("recall award", runRecallAward, formData);
}
