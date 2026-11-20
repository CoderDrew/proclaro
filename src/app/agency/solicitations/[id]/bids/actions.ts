"use server";

import { createServerClient } from "@/lib/supabase/server";
import { requireAgencyAction } from "../../../guard";
import { parseRecap } from "@/domain/recap/snapshot";
import { runDecideFlagged, runPickAward, type FlaggedDeps, type FlaggedResult, type PickDeps } from "./logic";

const NOT_AUTHORIZED: FlaggedResult = { ok: false, message: "You are not allowed to do that." };
const GENERIC: FlaggedResult = { ok: false, message: "Something went wrong. Reload the page and try again." };

/** Dependencies bound to the caller's own client (never the admin client). */
async function flaggedDeps(): Promise<FlaggedDeps> {
  const supabase = await createServerClient();
  return {
    async decide(args) {
      const { error } = await supabase.rpc("decide_flagged_bid", args);
      if (error) throw new Error(error.message);
    },
  };
}

/** Pick dependencies bound to the caller's own client: the public posted recap and public.pick_award. */
async function pickDeps(): Promise<PickDeps> {
  const supabase = await createServerClient();
  return {
    async postedRecap(solicitationId) {
      const { data, error } = await supabase.from("recaps").select("snapshot")
        .eq("solicitation_id", solicitationId).maybeSingle();
      if (error) throw new Error(error.message);
      const recap = data ? parseRecap(data.snapshot) : null;
      return recap?.kind === "recap" ? recap : null;
    },
    async pick(args) {
      // p_reason is nullable in SQL; the generated rpc type marks text arguments as string.
      const { error } = await supabase.rpc("pick_award", args as { p_solicitation_id: string; p_bid_id: string; p_reason: string });
      if (error) throw new Error(error.message);
    },
  };
}

function fields(formData: FormData): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of ["outcomeId", "decision", "reason", "solicitationId", "bidId"]) {
    const v = formData.get(k);
    if (typeof v === "string") out[k] = v;
  }
  return out;
}

/**
 * Agency only. Accepts or rejects one flagged bid with a reason (an append-only row; the latest counts). The database
 * checks the owning agency, the stage and that the outcome is still the bid's current flagged outcome.
 */
export async function decideFlagged(_prev: FlaggedResult | null, formData: FormData): Promise<FlaggedResult> {
  try {
    await requireAgencyAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  try {
    return await runDecideFlagged(fields(formData), await flaggedDeps());
  } catch (e) {
    console.error("decide flagged bid failed", e);
    return GENERIC;
  }
}

/**
 * Agency only. Records the agency's award choice from the posted recap (an append-only row; the latest counts). The
 * database checks the owning agency, the stage, that the bid is a recap row and the reason rule.
 */
export async function pickAward(_prev: FlaggedResult | null, formData: FormData): Promise<FlaggedResult> {
  try {
    await requireAgencyAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  try {
    return await runPickAward(fields(formData), await pickDeps());
  } catch (e) {
    console.error("pick award failed", e);
    return GENERIC;
  }
}
