"use server";

import { createServerClient } from "@/lib/supabase/server";
import { requireOfficeAction } from "../../guard";
import * as logic from "./logic";
import type { ActionResult, OfficeDeps } from "./logic";
import { parseStoredData } from "@/domain/solicitation/schema";
import { publishSolicitation, supabasePublishDeps, type PublishResult } from "./publish";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Dependencies bound to the caller's own client (RLS applies; never the admin client). */
async function officeDeps(): Promise<OfficeDeps> {
  const supabase = await createServerClient();
  return {
    now: () => new Date(),
    async call(fn, args) {
      // Argument shapes are fixed by logic.ts; the generated rpc types are per-function unions.
      const { error } = await supabase.rpc(fn, args as never);
      if (error) throw new Error(error.message);
    },
    async loadRow(id) {
      const { data, error } = await supabase
        .from("solicitations")
        .select("state, data, latest_submitted_at")
        .eq("id", id)
        .maybeSingle();
      if (error) throw new Error(error.message);
      if (!data) return null;
      const parsed = parseStoredData(data.data);
      if (!parsed) throw new Error("invalid_stored_data");
      return { state: data.state, latestSubmittedAt: data.latest_submitted_at, data: parsed };
    },
    async settings() {
      const [settings, holidays] = await Promise.all([
        supabase.from("settings").select("timezone").eq("id", 1).single(),
        supabase.from("holidays").select("day"),
      ]);
      if (settings.error) throw new Error(settings.error.message);
      if (holidays.error) throw new Error(holidays.error.message);
      return { tz: settings.data.timezone, holidays: holidays.data.map((h) => h.day) };
    },
    async loadAcks(id) {
      const { data, error } = await supabase.from("warning_acks").select("code, field").eq("solicitation_id", id);
      if (error) throw new Error(error.message);
      return data;
    },
  };
}

/** Office-only, id-checked, and never throwing for expected errors: returns { ok: false, message }. */
async function run(id: unknown, fn: (id: string, d: OfficeDeps) => Promise<ActionResult>): Promise<ActionResult> {
  try {
    await requireOfficeAction();
  } catch (e) {
    return { ok: false, message: logic.messageFor(e) };
  }
  if (typeof id !== "string" || !UUID.test(id)) return { ok: false, message: logic.messageFor(new Error("not_found")) };
  try {
    return await fn(id, await officeDeps());
  } catch (e) {
    console.error("office action failed", e);
    return { ok: false, message: logic.messageFor(e) };
  }
}

export async function startReview(id: string): Promise<ActionResult> {
  return run(id, (i, d) => logic.startReview(i, d));
}

export async function reassign(id: string, userId: string): Promise<ActionResult> {
  if (typeof userId !== "string" || !UUID.test(userId)) return { ok: false, message: logic.messageFor(new Error("not_found")) };
  return run(id, (i, d) => logic.reassign(i, userId, d));
}

export async function editAsReviewer(id: string, data: unknown, reason: string): Promise<ActionResult> {
  return run(id, (i, d) => logic.editAsReviewer(i, data, reason, d));
}

export async function returnToAgency(
  id: string,
  comments: { field: string | null; body: string }[],
): Promise<ActionResult> {
  return run(id, (i, d) => logic.returnToAgency(i, comments, d));
}

export async function sendToCheck(id: string): Promise<ActionResult> {
  return run(id, (i, d) => logic.sendToCheck(i, d));
}

export async function approveAlone(id: string): Promise<ActionResult> {
  return run(id, (i, d) => logic.approveAlone(i, d));
}

export async function reopenReview(id: string, reason: string): Promise<ActionResult> {
  return run(id, (i, d) => logic.reopenReview(i, reason, d));
}

export async function approveCheck(id: string): Promise<ActionResult> {
  return run(id, (i, d) => logic.approveCheck(i, d));
}

export async function disagree(id: string, comment: string, field: string | null): Promise<ActionResult> {
  return run(id, (i, d) => logic.disagree(i, comment, field, d));
}

export async function acknowledgeWarning(id: string, code: string, field: string | null): Promise<ActionResult> {
  return run(id, (i, d) => logic.acknowledge(i, code, field, d));
}

/** Renders, stores and publishes an approved solicitation. Typed results only; never throws. */
export async function publish(id: string): Promise<PublishResult> {
  let ctx;
  try {
    ctx = await requireOfficeAction();
  } catch (e) {
    return { ok: false, message: logic.messageFor(e), errors: [] };
  }
  if (typeof id !== "string" || !UUID.test(id)) {
    return { ok: false, message: logic.messageFor(new Error("not_found")), errors: [] };
  }
  try {
    return await publishSolicitation(id, supabasePublishDeps(await createServerClient(), ctx.userId));
  } catch (e) {
    console.error("publish action failed", e);
    return { ok: false, message: logic.messageFor(e), errors: [] };
  }
}
