"use server";

import { randomUUID } from "node:crypto";
import { parseStoredData } from "@/domain/solicitation/schema";
import { todayIn } from "@/domain/time";
import { createServerClient } from "@/lib/supabase/server";
import { requireAgencyAction } from "../../../../guard";
import { prepareDraftData, safeFileName } from "../../logic";
import {
  addendumMessageFor, parseAnswerInput, runAddendumCall, runStartAddendum, runSubmitAddendum,
  type AddendumResult, type AddendumSubmitResult, type StartAddendumResult,
} from "./logic";

// Every action returns plain copy instead of throwing: Next strips thrown messages from server actions in production.

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const NOT_AUTHORIZED = { ok: false as const, message: addendumMessageFor(new Error("not_authorized")) };
const NOT_FOUND = { ok: false as const, message: addendumMessageFor(new Error("not_found")) };

async function guard(): Promise<boolean> {
  try {
    await requireAgencyAction();
    return true;
  } catch {
    return false;
  }
}

const isId = (v: unknown): v is string => typeof v === "string" && UUID.test(v);

/** The addendum row as the caller's client sees it (RLS: owning agency or office), or null. */
async function loadAddendumRow(addendumId: string) {
  const supabase = await createServerClient();
  const { data, error } = await supabase
    .from("addenda").select("id, solicitation_id, state, data, narrative").eq("id", addendumId).maybeSingle();
  if (error) throw new Error(error.message);
  return { supabase, row: data };
}

function rpcError(error: { message: string } | null): void {
  if (error) throw new Error(error.message);
}

/** Agency only. Starts an addendum on a published solicitation still open for bids. */
export async function startAddendum(solicitationId: string): Promise<StartAddendumResult> {
  if (!(await guard())) return NOT_AUTHORIZED;
  const supabase = await createServerClient();
  return runStartAddendum(solicitationId, {
    async start(sid) {
      const { data, error } = await supabase.rpc("start_addendum", { p_solicitation_id: sid });
      rpcError(error);
      return data as string;
    },
  });
}

/** Agency only. Autosave: the full data (zod-checked, attachments in this solicitation's folder) and the narrative. */
export async function saveAddendum(addendumId: string, data: unknown, narrative: unknown): Promise<AddendumResult> {
  if (!(await guard())) return NOT_AUTHORIZED;
  if (!isId(addendumId) || typeof narrative !== "string") return NOT_FOUND;
  return runAddendumCall(async () => {
    const { supabase, row } = await loadAddendumRow(addendumId);
    if (!row) throw new Error("not_found");
    let parsed;
    try {
      parsed = prepareDraftData(row.solicitation_id, data);
    } catch (e) {
      throw new Error(e instanceof Error && e.message === "invalid_attachment_path" ? e.message : "invalid_data");
    }
    const { error } = await supabase.rpc("save_addendum", {
      p_addendum_id: addendumId, p_data: JSON.parse(JSON.stringify(parsed)), p_narrative: narrative,
    });
    rpcError(error);
  });
}

/** Agency only. A signed upload URL in the attachments bucket; storage allows it while the addendum is a draft. */
export async function createAddendumUploadUrl(addendumId: string, fileName: string):
  Promise<{ ok: true; path: string; token: string } | { ok: false; message: string }> {
  if (!(await guard())) return NOT_AUTHORIZED;
  if (!isId(addendumId)) return NOT_FOUND;
  try {
    const { supabase, row } = await loadAddendumRow(addendumId);
    if (!row) return NOT_FOUND;
    if (row.state !== "draft") return { ok: false, message: addendumMessageFor(new Error("invalid_state")) };
    const path = `solicitations/${row.solicitation_id}/${randomUUID().slice(0, 8)}-${safeFileName(String(fileName))}`;
    const { data, error } = await supabase.storage.from("attachments").createSignedUploadUrl(path);
    if (error || !data) throw new Error(error?.message ?? "upload_url_failed");
    return { ok: true, path: data.path, token: data.token };
  } catch (e) {
    console.error("addendum upload url failed", e);
    return { ok: false, message: "The upload could not be started. Try again." };
  }
}

/** Agency only. Re-validates the stored addendum, then submit_addendum. */
export async function submitAddendum(addendumId: string): Promise<AddendumSubmitResult> {
  if (!(await guard())) return NOT_AUTHORIZED;
  if (!isId(addendumId)) return NOT_FOUND;
  const supabase = await createServerClient();
  try {
    return await runSubmitAddendum(addendumId, {
      async loadAddendum(id) {
        const { row } = await loadAddendumRow(id);
        if (!row) return null;
        const { data: sol, error } = await supabase
          .from("solicitations").select("data").eq("id", row.solicitation_id).maybeSingle();
        if (error) throw new Error(error.message);
        const data = parseStoredData(row.data);
        const baseData = sol ? parseStoredData(sol.data) : null;
        if (!data || !baseData) throw new Error("invalid_data");
        return { state: row.state, data, narrative: row.narrative, baseData };
      },
      async validationContext() {
        const [settings, holidays] = await Promise.all([
          supabase.from("settings").select("timezone").eq("id", 1).single(),
          supabase.from("holidays").select("day"),
        ]);
        if (settings.error) throw new Error(settings.error.message);
        if (holidays.error) throw new Error(holidays.error.message);
        const tz = settings.data.timezone;
        const now = new Date();
        return { tz, holidays: holidays.data.map((h) => h.day), submissionDate: todayIn(tz, now), mode: "addendum", now };
      },
      async submit(id) {
        const { error } = await supabase.rpc("submit_addendum", { p_addendum_id: id });
        rpcError(error);
      },
    });
  } catch (e) {
    console.error("submit addendum failed", e);
    return { ok: false, message: addendumMessageFor(e) };
  }
}

/** Agency only, from draft. Terminal; questions picked into it go back to open. */
export async function withdrawAddendum(addendumId: string, reason: unknown): Promise<AddendumResult> {
  if (!(await guard())) return NOT_AUTHORIZED;
  if (!isId(addendumId)) return NOT_FOUND;
  const r = typeof reason === "string" ? reason.trim() : "";
  if (r === "") return { ok: false, message: addendumMessageFor(new Error("reason_required")) };
  const supabase = await createServerClient();
  return runAddendumCall(async () => {
    rpcError((await supabase.rpc("withdraw_addendum", { p_addendum_id: addendumId, p_reason: r })).error);
  });
}

/** Agency only. Answers one open question in this draft addendum (insert or replace). */
export async function saveAnswer(addendumId: string, questionId: string, publishedQuestion: unknown, answer: unknown):
  Promise<AddendumResult> {
  if (!(await guard())) return NOT_AUTHORIZED;
  if (!isId(addendumId) || !isId(questionId)) return NOT_FOUND;
  const p = parseAnswerInput(publishedQuestion, answer);
  if (!p.ok) return p;
  const supabase = await createServerClient();
  return runAddendumCall(async () => {
    rpcError((await supabase.rpc("save_addendum_answer", {
      p_addendum_id: addendumId, p_question_id: questionId,
      p_published_question: p.value.publishedQuestion, p_answer: p.value.answer,
    })).error);
  });
}

/** Agency only. Takes one answer back out of this draft addendum. */
export async function removeAnswer(addendumId: string, questionId: string): Promise<AddendumResult> {
  if (!(await guard())) return NOT_AUTHORIZED;
  if (!isId(addendumId) || !isId(questionId)) return NOT_FOUND;
  const supabase = await createServerClient();
  return runAddendumCall(async () => {
    rpcError((await supabase.rpc("remove_addendum_answer", { p_addendum_id: addendumId, p_question_id: questionId })).error);
  });
}
