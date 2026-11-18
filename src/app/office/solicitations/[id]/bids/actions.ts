"use server";

import { createServerClient } from "@/lib/supabase/server";
import { requireOfficeAction } from "../../../guard";
import type { ActionResult } from "../logic";
import { runLogOriginal, runVoidOriginal, type LogOriginalInput, type OriginalsDeps } from "./logic";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NOT_AUTHORIZED: ActionResult = { ok: false, message: "You are not allowed to do that." };
const GENERIC: ActionResult = { ok: false, message: "Something went wrong. Reload the page and try again." };

/** Dependencies bound to the caller's own client (never the admin client). */
async function originalsDeps(): Promise<OriginalsDeps> {
  const supabase = await createServerClient();
  return {
    now: () => new Date(),
    async tz() {
      const { data, error } = await supabase.from("settings").select("timezone").eq("id", 1).single();
      if (error) throw new Error(error.message);
      return data.timezone;
    },
    async call(fn, args) {
      // Argument shapes are fixed by logic.ts; the generated rpc types are per-function unions.
      const { error } = await supabase.rpc(fn, args as never);
      if (error) throw new Error(error.message);
    },
  };
}

/** Office only. Logs a mailed signed form or paper bid bond against a bid reference and version. */
export async function logOriginal(solicitationId: string, input: LogOriginalInput): Promise<ActionResult> {
  try {
    await requireOfficeAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  if (typeof solicitationId !== "string" || !UUID.test(solicitationId) || !input || typeof input !== "object") {
    return { ok: false, message: "That solicitation was not found." };
  }
  try {
    return await runLogOriginal(solicitationId, {
      reference: String(input.reference ?? ""), version: String(input.version ?? ""),
      item: String(input.item ?? ""), receivedAt: String(input.receivedAt ?? ""),
    }, await originalsDeps());
  } catch (e) {
    console.error("log original failed", e);
    return GENERIC;
  }
}

/** Office only. Voids an earlier receipt, with a reason. */
export async function voidOriginal(entryId: string, reason: string): Promise<ActionResult> {
  try {
    await requireOfficeAction();
  } catch {
    return NOT_AUTHORIZED;
  }
  if (typeof entryId !== "string" || !UUID.test(entryId)) return { ok: false, message: "That log entry was not found." };
  try {
    return await runVoidOriginal(entryId, typeof reason === "string" ? reason : "", await originalsDeps());
  } catch (e) {
    console.error("void original failed", e);
    return GENERIC;
  }
}
