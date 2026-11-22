"use server";

import { createServerClient } from "@/lib/supabase/server";
import { requireOfficeAction } from "../../../../guard";
import * as logic from "./logic";
import type { AddendumActionResult, AddendumOfficeDeps, CloseReason } from "./logic";
import { publishAddendum, supabasePublishAddendumDeps, type PublishAddendumResult } from "./publish";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Bound to the caller's own client (RLS and the definer functions' checks apply; never the admin client). */
async function deps(): Promise<AddendumOfficeDeps> {
  const supabase = await createServerClient();
  return {
    async call(fn, args) {
      // Argument shapes are fixed by logic.ts; the generated rpc types are per-function unions.
      const { error } = await supabase.rpc(fn, args as never);
      if (error) throw new Error(error.message);
    },
  };
}

function run(id: unknown, fn: (id: string, d: AddendumOfficeDeps) => Promise<AddendumActionResult>) {
  return logic.withOffice(requireOfficeAction, id, async (i) => fn(i, await deps())) as Promise<AddendumActionResult>;
}

export async function startAddendumReview(id: string): Promise<AddendumActionResult> {
  return run(id, logic.startReview);
}

export async function reassignAddendumReview(id: string, userId: string): Promise<AddendumActionResult> {
  if (typeof userId !== "string" || !UUID.test(userId)) {
    return { ok: false, message: "Choose an office staff member." };
  }
  return run(id, (i, d) => logic.reassign(i, userId, d));
}

export async function returnAddendum(
  id: string, comments: { field: string | null; body: string }[],
): Promise<AddendumActionResult> {
  return run(id, (i, d) => logic.returnAddendum(i, comments, d));
}

export async function sendAddendumToCheck(id: string): Promise<AddendumActionResult> {
  return run(id, logic.sendToCheck);
}

export async function approveAddendumCheck(id: string): Promise<AddendumActionResult> {
  return run(id, logic.approveCheck);
}

export async function disagreeAddendum(id: string, comment: string): Promise<AddendumActionResult> {
  return run(id, (i, d) => logic.disagree(i, comment, d));
}

export async function approveAddendumAlone(id: string): Promise<AddendumActionResult> {
  return run(id, logic.approveAlone);
}

export async function reopenAddendumReview(id: string, reason: string): Promise<AddendumActionResult> {
  return run(id, (i, d) => logic.reopen(i, reason, d));
}

export async function withdrawAddendumAsOffice(id: string, reason: string): Promise<AddendumActionResult> {
  return run(id, (i, d) => logic.withdraw(i, reason, d));
}

/** Closes a question as a duplicate or out of scope (office only). */
export async function closeQuestion(questionId: string, reason: CloseReason): Promise<AddendumActionResult> {
  try {
    await requireOfficeAction();
  } catch (e) {
    return { ok: false, message: logic.addendumMessageFor(e) };
  }
  try {
    // logic.closeQuestion checks the id itself, so a bad id reads "question not found", not "addendum not found".
    return await logic.closeQuestion(questionId, reason, await deps());
  } catch (e) {
    console.error("close question failed", e);
    return { ok: false, message: logic.addendumMessageFor(e) };
  }
}

/** Renders, stores and publishes an approved addendum. Typed results only; never throws. */
export async function publishAddendumAction(addendumId: string): Promise<PublishAddendumResult> {
  let ctx;
  try {
    ctx = await requireOfficeAction();
  } catch (e) {
    return { ok: false, message: logic.addendumMessageFor(e), errors: [] };
  }
  if (typeof addendumId !== "string" || !UUID.test(addendumId)) {
    return { ok: false, message: logic.addendumMessageFor(new Error("not_found")), errors: [] };
  }
  try {
    return await publishAddendum(addendumId, supabasePublishAddendumDeps(await createServerClient(), ctx.userId));
  } catch (e) {
    console.error("publish addendum action failed", e);
    return { ok: false, message: logic.addendumMessageFor(e), errors: [] };
  }
}
